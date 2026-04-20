import os
import shutil
import traceback
from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.filechooser import FileChooserListView
from kivy.uix.popup import Popup
from kivy.utils import platform
from kivy.clock import Clock

class PDFTestApp(App):
    def build(self):
        self.root_layout = BoxLayout(orientation='vertical', padding=20, spacing=20)
        
        # Status Label (English)
        self.status_label = Label(
            text="Step 1: Click 'Grant Permission'\nStep 2: Allow 'All Files Access' in Settings\nStep 3: Return here and click 'Select PDF'", 
            size_hint_y=None, 
            height=300,
            halign='center'
        )
        self.root_layout.add_widget(self.status_label)
        
        # Button 1: Request Permission Manual Trigger
        self.perm_btn = Button(text="1. Grant All File Permission", size_hint_y=None, height=120)
        self.perm_btn.bind(on_release=self.open_permission_settings)
        self.root_layout.add_widget(self.perm_btn)
        
        # Button 2: Open File Chooser
        self.select_btn = Button(text="2. Select and Open PDF", size_hint_y=None, height=120)
        self.select_btn.bind(on_release=self.open_file_chooser)
        self.root_layout.add_widget(self.select_btn)
        
        self.webview = None
        return self.root_layout

    def open_permission_settings(self, instance):
        if platform != 'android':
            self.status_label.text = "Running on Desktop (No Android permission needed)"
            return

        try:
            from jnius import autoclass
            # Open Android Settings for All Files Access
            mActivity = autoclass('org.kivy.android.PythonActivity').mActivity
            Intent = autoclass('android.content.Intent')
            Settings = autoclass('android.provider.Settings')
            Uri = autoclass('android.net.Uri')
            uri = Uri.fromParts("package", mActivity.getPackageName(), None)
            intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
            intent.setData(uri)
            mActivity.startActivity(intent)
            self.status_label.text = "Settings opened.\nPlease enable the switch and come back."
        except Exception as e:
            self.status_label.text = f"Permission Error:\n{str(e)}"

    def open_file_chooser(self, instance):
        # Default path to /storage/emulated/0 (Standard SD Card Root)
        path = "/storage/emulated/0" if platform == 'android' else os.getcwd()
        fc = FileChooserListView(path=path, filters=['*.pdf'])
        
        content = BoxLayout(orientation='vertical')
        content.add_widget(fc)
        
        btn_layout = BoxLayout(size_hint_y=None, height=100)
        select_btn = Button(text="Open Selected File")
        cancel_btn = Button(text="Cancel")
        btn_layout.add_widget(select_btn)
        btn_layout.add_widget(cancel_btn)
        content.add_widget(btn_layout)
        
        popup = Popup(title="Browse PDF File", content=content, size_hint=(0.9, 0.9))
        
        def on_select(btn):
            if fc.selection:
                popup.dismiss()
                self.start_pdf_process(fc.selection[0])
            else:
                self.status_label.text = "No file selected!"
        
        select_btn.bind(on_release=on_select)
        cancel_btn.bind(on_release=popup.dismiss)
        popup.open()

    def start_pdf_process(self, file_path):
        filename = os.path.basename(file_path)
        self.status_label.text = f"Loading: {filename}\nCopying to internal cache..."
        Clock.schedule_once(lambda dt: self.copy_and_show(file_path), 0.5)

    def copy_and_show(self, src_path):
        try:
            from jnius import autoclass
            mActivity = autoclass('org.kivy.android.PythonActivity').mActivity
            internal_dir = mActivity.getFilesDir().getAbsolutePath()
            
            # Copy PDF to internal storage (bypass CORS)
            dest_path = os.path.join(internal_dir, "temp.pdf")
            if os.path.exists(dest_path): os.remove(dest_path)
            shutil.copy2(src_path, dest_path)
            
            # Copy pdfjs engine if not exists
            dest_pdfjs = os.path.join(internal_dir, "pdfjs")
            src_pdfjs = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pdfjs")
            if not os.path.exists(dest_pdfjs) and os.path.exists(src_pdfjs):
                shutil.copytree(src_pdfjs, dest_pdfjs)

            self.status_label.text = "Creating WebView UI..."
            Clock.schedule_once(lambda dt: self.init_webview(dest_path), 1.0)
        except Exception as e:
            self.status_label.text = f"IO Error:\n{str(e)}"

    def init_webview(self, pdf_path):
        from android.runnable import run_on_main_thread
        @run_on_main_thread
        def _setup():
            try:
                from jnius import autoclass
                mActivity = autoclass('org.kivy.android.PythonActivity').mActivity
                if not self.webview:
                    WebView = autoclass('android.webkit.WebView')
                    self.webview = WebView(mActivity)
                    s = self.webview.getSettings()
                    s.setJavaScriptEnabled(True)
                    s.setAllowFileAccess(True)
                    s.setDomStorageEnabled(True)
                    self.webview.setLayerType(1, None) # Software acceleration for stability
                    
                    params = autoclass('android.view.ViewGroup$LayoutParams')
                    mActivity.getWindow().getDecorView().addView(self.webview, params(-1, -1))
                
                self.webview.setVisibility(0)
                self.webview.bringToFront()
                
                internal = mActivity.getFilesDir().getAbsolutePath()
                url = f"file://{internal}/pdfjs/web/viewer.html?file=file://{pdf_path}"
                self.webview.loadUrl(url)
                self.status_label.text = "Success: WebView Loaded"
            except Exception as e:
                self.status_label.text = f"WebView Error:\n{str(e)}"
        _setup()

if __name__ == '__main__':
    PDFTestApp().run()
