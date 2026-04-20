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
        self.status_label = Label(text="파일 권한 확인 중...", size_hint_y=None, height=200)
        self.root_layout.add_widget(self.status_label)
        
        self.select_btn = Button(text="PDF 파일 선택 (권한 필요)", size_hint_y=None, height=150, disabled=True)
        self.select_btn.bind(on_release=self.open_file_chooser)
        self.root_layout.add_widget(self.select_btn)
        
        self.webview = None
        # 앱 시작 1초 뒤 권한 요청 실행
        Clock.schedule_once(self.check_and_ask_permissions, 1)
        return self.root_layout

    def check_and_ask_permissions(self, dt):
        if platform != 'android':
            self.status_label.text = "윈도우 환경입니다."
            self.select_btn.disabled = False
            return

        try:
            from android.permissions import request_permissions, Permission
            # 1. 기본 읽기/쓰기 권한 요청
            def perm_cb(permissions, grants):
                if all(grants):
                    self.status_label.text = "기본 권한 승인됨. 모든 파일 권한 확인..."
                    self.ask_manage_storage()
                else:
                    self.status_label.text = "기본 권한이 거부되었습니다."

            request_permissions([Permission.READ_EXTERNAL_STORAGE, Permission.WRITE_EXTERNAL_STORAGE], perm_cb)
        except Exception as e:
            self.status_label.text = f"권한 요청 오류: {e}"

    def ask_manage_storage(self):
        try:
            from jnius import autoclass
            Env = autoclass('android.os.Environment')
            if hasattr(Env, 'isExternalStorageManager'):
                if not Env.isExternalStorageManager():
                    # 설정 화면으로 이동
                    self.status_label.text = "모든 파일 관리 권한을 허용해 주세요."
                    mActivity = autoclass('org.kivy.android.PythonActivity').mActivity
                    Intent = autoclass('android.content.Intent')
                    Settings = autoclass('android.provider.Settings')
                    Uri = autoclass('android.net.Uri')
                    uri = Uri.fromParts("package", mActivity.getPackageName(), None)
                    intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                    intent.setData(uri)
                    mActivity.startActivity(intent)
                    # 승인하고 돌아오기를 기다림
                    Clock.schedule_interval(self.wait_for_storage_permission, 1)
                else:
                    self.on_all_permissions_ready()
            else:
                self.on_all_permissions_ready()
        except:
            self.on_all_permissions_ready()

    def wait_for_storage_permission(self, dt):
        from jnius import autoclass
        Env = autoclass('android.os.Environment')
        if Env.isExternalStorageManager():
            self.on_all_permissions_ready()
            return False # 스케줄 중단
        return True

    def on_all_permissions_ready(self):
        self.status_label.text = "모든 권한 준비 완료.\n이제 파일을 선택할 수 있습니다."
        self.select_btn.disabled = False

    def open_file_chooser(self, instance):
        # /storage/emulated/0 가 기본 경로
        path = "/storage/emulated/0" if platform == 'android' else os.getcwd()
        fc = FileChooserListView(path=path, filters=['*.pdf'])
        
        content = BoxLayout(orientation='vertical')
        content.add_widget(fc)
        
        select_btn = Button(text="선택한 파일 열기", size_hint_y=None, height=120)
        content.add_widget(select_btn)
        
        popup = Popup(title="PDF 선택 (경로: /sdcard)", content=content, size_hint=(0.9, 0.9))
        
        def on_select(btn):
            if fc.selection:
                popup.dismiss()
                self.start_pdf_process(fc.selection[0])
        
        select_btn.bind(on_release=on_select)
        popup.open()

    def start_pdf_process(self, file_path):
        self.status_label.text = f"선택됨: {os.path.basename(file_path)}\n복사 중..."
        Clock.schedule_once(lambda dt: self.copy_and_show(file_path), 0.5)

    def copy_and_show(self, src_path):
        try:
            from jnius import autoclass
            mActivity = autoclass('org.kivy.android.PythonActivity').mActivity
            internal_dir = mActivity.getFilesDir().getAbsolutePath()
            
            dest_path = os.path.join(internal_dir, "temp.pdf")
            if os.path.exists(dest_path): os.remove(dest_path)
            shutil.copy2(src_path, dest_path)
            
            dest_pdfjs = os.path.join(internal_dir, "pdfjs")
            src_pdfjs = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pdfjs")
            if not os.path.exists(dest_pdfjs) and os.path.exists(src_pdfjs):
                shutil.copytree(src_pdfjs, dest_pdfjs)

            self.status_label.text = "WebView 생성 중..."
            Clock.schedule_once(lambda dt: self.init_webview(dest_path), 1.0)
        except Exception as e:
            self.status_label.text = f"오류 발생: {e}"

    def init_webview(self, pdf_path):
        from android.runnable import run_on_main_thread
        @run_on_main_thread
        def _setup():
            try:
                from jnius import autoclass
                mActivity = autoclass('org.kivy.android.PythonActivity').mActivity
                if not self.webview:
                    self.webview = autoclass('android.webkit.WebView')(mActivity)
                    s = self.webview.getSettings()
                    s.setJavaScriptEnabled(True); s.setAllowFileAccess(True); s.setDomStorageEnabled(True)
                    self.webview.setLayerType(1, None)
                    mActivity.getWindow().getDecorView().addView(self.webview, autoclass('android.view.ViewGroup$LayoutParams')(-1, -1))
                self.webview.setVisibility(0); self.webview.bringToFront()
                internal = mActivity.getFilesDir().getAbsolutePath()
                url = f"file://{internal}/pdfjs/web/viewer.html?file=file://{pdf_path}"
                self.webview.loadUrl(url)
                self.status_label.text = "WebView 실행 성공"
            except Exception as e:
                self.status_label.text = f"WebView 에러: {e}"
        _setup()

if __name__ == '__main__':
    PDFTestApp().run()
