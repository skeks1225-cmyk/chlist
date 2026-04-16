import os
import json
import threading
import socket
import time
from http.server import SimpleHTTPRequestHandler, HTTPServer
from openpyxl import load_workbook

from kivy.app import App
from kivy.lang import Builder
from kivy.core.window import Window
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.screenmanager import ScreenManager, Screen
from kivy.uix.recycleview import RecycleView
from kivy.properties import StringProperty, BooleanProperty, NumericProperty, DictProperty, ListProperty
from kivy.uix.popup import Popup
from kivy.uix.filechooser import FileChooserListView
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.textinput import TextInput
from kivy.uix.scrollview import ScrollView
from kivy.core.text import LabelBase
from kivy.utils import platform
from kivy.clock import Clock
from kivy.metrics import dp

# --- 1. 한글 폰트 설정 ---
FONT_NAME = "font.ttf"
if platform == 'android':
    FONT_NAME = os.path.join(os.path.dirname(__file__), "font.ttf")

if os.path.exists(FONT_NAME):
    try:
        LabelBase.register(name="Roboto", fn_regular=FONT_NAME)
        from kivy.core.text import Label as CoreLabel
        CoreLabel.register("Roboto", FONT_NAME)
    except: pass

# --- 2. UI 디자인 (WebView 영역 확보) ---
KV_UI = """
<Label>:
    font_name: 'Roboto'
<Button>:
    font_name: 'Roboto'
<TextInput>:
    font_name: 'Roboto'
<FileChooserLabel>:
    font_name: 'Roboto'

<ListScreen>:
    BoxLayout:
        orientation: 'vertical'
        canvas.before:
            Color:
                rgba: 0.1, 0.1, 0.1, 1
            Rectangle:
                pos: self.pos
                size: self.size

        BoxLayout:
            size_hint_y: None
            height: '60dp'
            padding: '5dp'
            spacing: '5dp'
            canvas.before:
                Color:
                    rgba: 0.2, 0.2, 0.2, 1
                Rectangle:
                    pos: self.pos
                    size: self.size
            Button:
                text: '접속설정'
                on_release: app.open_smb_settings()
            Button:
                text: '엑셀선택'
                on_release: app.select_source('file')
            Button:
                text: 'PDF폴더'
                on_release: app.select_source('dir')
            Button:
                text: '저장'
                background_color: 0.2, 0.7, 0.3, 1
                on_release: app.save_to_excel()

        BoxLayout:
            size_hint_y: None
            height: '45dp'
            canvas.before:
                Color:
                    rgba: 0.25, 0.25, 0.25, 1
                Rectangle:
                    pos: self.pos
                    size: self.size
            Button:
                text: 'No' + app.sort_indicator_no
                size_hint_x: 0.1
                on_release: app.sort_by('no')
            Button:
                text: '품목코드' + app.sort_indicator_code
                size_hint_x: 0.3
                on_release: app.sort_by('item_code')
            Button:
                text: '수량' + app.sort_indicator_qty
                size_hint_x: 0.15
                on_release: app.sort_by('quantity')
            Button:
                text: '완료' + app.sort_indicator_comp
                size_hint_x: 0.15
                on_release: app.sort_by('complete')
            Button:
                text: '부족' + app.sort_indicator_short
                size_hint_x: 0.15
                on_release: app.sort_by('shortage')
            Button:
                text: '재작업' + app.sort_indicator_rew
                size_hint_x: 0.15
                on_release: app.sort_by('rework')

        CheckSheetRV:
            id: rv
            viewclass: 'RowWidget'
            RecycleBoxLayout:
                default_size: None, dp(60)
                default_size_hint: 1, None
                size_hint_y: None
                height: self.minimum_height
                orientation: 'vertical'
                spacing: '1dp'

<ViewerScreen>:
    BoxLayout:
        orientation: 'vertical'
        canvas.before:
            Color:
                rgba: 0, 0, 0, 1
            Rectangle:
                pos: self.pos
                size: self.size
        
        BoxLayout:
            size_hint_y: None
            height: dp(60)
            padding: dp(5)
            canvas.before:
                Color:
                    rgba: 0.2, 0.2, 0.2, 1
                Rectangle:
                    pos: self.pos
                    size: self.size
            Label:
                text: app.viewer_title
                font_size: '18sp'
            Button:
                text: '닫기'
                size_hint_x: None
                width: dp(100)
                on_release: app.close_viewer()

        # 벡터 뷰어 (WebView가 이 자리에 배치됩니다)
        BoxLayout:
            id: webview_container
            canvas.before:
                Color:
                    rgba: 0.1, 0.1, 0.1, 1
                Rectangle:
                    pos: self.pos
                    size: self.size

        BoxLayout:
            size_hint_y: None
            height: dp(80)
            spacing: dp(10)
            padding: [dp(10), dp(10)]
            canvas.before:
                Color:
                    rgba: 0.15, 0.15, 0.15, 1
                Rectangle:
                    pos: self.pos
                    size: self.size
            Button:
                text: '완료'
                background_color: app.color_comp
                on_release: app.update_viewer_status('complete')
            Button:
                text: '부족'
                background_color: app.color_short
                on_release: app.update_viewer_status('shortage')
            Button:
                text: '재작업'
                background_color: app.color_rew
                on_release: app.update_viewer_status('rework')

<RowWidget>:
    orientation: 'horizontal'
    padding: [2, 2]
    canvas.before:
        Color:
            rgba: 0.2, 0.2, 0.2, 1
        Rectangle:
            pos: self.pos
            size: self.size
    Label:
        text: root.no
        size_hint_x: 0.1
    Button:
        text: root.item_code
        size_hint_x: 0.3
        background_normal: ''
        background_color: 0.2, 0.4, 0.6, 1
        on_release: root.open_pdf()
    Label:
        text: root.quantity
        size_hint_x: 0.15
    Button:
        text: 'V' if root.complete else ''
        size_hint_x: 0.15
        background_normal: ''
        background_color: (0, 1, 0, 0.5) if root.complete else (0.3, 0.3, 0.3, 1)
        on_release: root.on_checkbox_active('complete')
    Button:
        text: 'V' if root.shortage else ''
        size_hint_x: 0.15
        background_normal: ''
        background_color: (1, 1, 0, 0.5) if root.shortage else (0.3, 0.3, 0.3, 1)
        on_release: root.on_checkbox_active('shortage')
    Button:
        text: 'V' if root.rework else ''
        size_hint_x: 0.15
        background_normal: ''
        background_color: (1, 0, 0, 0.5) if root.rework else (0.3, 0.3, 0.3, 1)
        on_release: root.on_checkbox_active('rework')
"""

if platform == 'android':
    Window.softinput_mode = 'below_target'

SETTINGS_FILE = 'settings.json'
LOCAL_BASE = "/sdcard/Download/CheckSheet" if platform == 'android' else os.path.join(os.getcwd(), "CheckSheet_Data")

class ListScreen(Screen): pass
class ViewerScreen(Screen): pass
class CheckSheetRV(RecycleView): pass

class RowWidget(BoxLayout):
    no = StringProperty(''); item_code = StringProperty(''); quantity = StringProperty('')
    complete = BooleanProperty(False); shortage = BooleanProperty(False); rework = BooleanProperty(False)
    def on_checkbox_active(self, ct): App.get_running_app().update_item_status(self.item_code, self.no, ct)
    def open_pdf(self):
        app = App.get_running_app(); rv = app.root.get_screen('list').ids.rv
        for i, d in enumerate(rv.data):
            if d['item_code'] == self.item_code and d['no'] == self.no:
                app.open_pdf_viewer(i); break

# --- 3. 로컬 파일 서버 (WebView에 파일 공급용) ---
class PDFServer(SimpleHTTPRequestHandler):
    def log_message(self, format, *args): pass # 로그 생략

def run_server(port, directory):
    os.chdir(directory)
    httpd = HTTPServer(('127.0.0.1', port), PDFServer)
    httpd.serve_forever()

class CheckSheetApp(App):
    excel_path = StringProperty(''); pdf_folder_path = StringProperty('')
    pdf_source = StringProperty('local'); smb_config = DictProperty({'ip': '', 'user': '', 'pass': ''})
    sort_indicator_no = StringProperty(''); sort_indicator_code = StringProperty(''); sort_indicator_qty = StringProperty('')
    sort_indicator_comp = StringProperty(''); sort_indicator_short = StringProperty(''); sort_indicator_rew = StringProperty('')
    sort_states = {}
    viewer_title = StringProperty('')
    current_view_idx = NumericProperty(-1)
    color_comp = ListProperty([0.3, 0.3, 0.3, 1]); color_short = ListProperty([0.3, 0.3, 0.3, 1]); color_rew = ListProperty([0.3, 0.3, 0.3, 1])
    
    android_webview = None
    server_started = False

    def build(self):
        self.load_settings()
        Builder.load_string(KV_UI)
        sm = ScreenManager()
        sm.add_widget(ListScreen(name='list'))
        sm.add_widget(ViewerScreen(name='viewer'))
        return sm

    def on_start(self):
        if platform == 'android': Clock.schedule_once(self.ask_permissions, 1)
        if self.excel_path and os.path.exists(self.excel_path): self.load_excel_data(self.excel_path)

    def ask_permissions(self, dt):
        try:
            from android.permissions import request_permissions, Permission
            from jnius import autoclass
            request_permissions([Permission.READ_EXTERNAL_STORAGE, Permission.WRITE_EXTERNAL_STORAGE, Permission.INTERNET, Permission.ACCESS_NETWORK_STATE])
            Env = autoclass('android.os.Environment')
            if hasattr(Env, 'isExternalStorageManager'):
                if not Env.isExternalStorageManager():
                    Context = autoclass('org.kivy.android.PythonActivity').mActivity
                    Intent = autoclass('android.content.Intent')
                    Settings = autoclass('android.provider.Settings')
                    intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                    uri = autoclass('android.net.Uri').fromParts("package", Context.getPackageName(), None)
                    intent.setData(uri); Context.startActivity(intent)
        except: pass

    def start_local_server(self, directory):
        if not self.server_started:
            threading.Thread(target=run_server, args=(8080, directory), daemon=True).start()
            self.server_started = True

    def open_pdf_viewer(self, idx):
        self.current_view_idx = idx
        item = self.root.get_screen('list').ids.rv.data[idx]
        self.viewer_title = item['item_code']
        self.refresh_viewer_ui()
        
        base_path = self.pdf_folder_path if self.pdf_folder_path else LOCAL_BASE
        if not os.path.exists(base_path):
            self.show_error_popup("PDF 폴더를 먼저 선택해주세요.")
            return

        self.root.current = 'viewer'
        
        if platform == 'android':
            self.start_local_server(base_path)
            Clock.schedule_once(lambda dt: self.init_android_webview(item['item_code']), 0.5)
        else:
            self.show_error_popup("벡터 뷰어는 안드로이드에서만 작동합니다.")

    def init_android_webview(self, filename):
        from jnius import autoclass, cast
        from android.runnable import run_on_main_thread

        @run_on_main_thread
        def setup_webview():
            mActivity = autoclass('org.kivy.android.PythonActivity').mActivity
            WebView = autoclass('android.webkit.WebView')
            WebViewClient = autoclass('android.webkit.WebViewClient')
            
            if not self.android_webview:
                self.android_webview = WebView(mActivity)
                self.android_webview.getSettings().setJavaScriptEnabled(True)
                self.android_webview.getSettings().setBuiltInZoomControls(True)
                self.android_webview.getSettings().setDisplayZoomControls(False)
                self.android_webview.getSettings().setSupportZoom(True)
                self.android_webview.setWebViewClient(WebViewClient())
                
                # Kivy 컨테이너에 WebView 추가
                container = self.root.get_screen('viewer').ids.webview_container
                # 안드로이드 뷰를 Kivy 위에 올리는 복잡한 과정 생략하고 단순히 레이아웃에 추가
                mActivity.addContentView(self.android_webview, autoclass('android.view.ViewGroup$LayoutParams')(-1, -1))

            self.android_webview.setVisibility(autoclass('android.view.View').VISIBLE)
            # 구글 Docs 뷰어를 통한 벡터 렌더링 (가장 확실한 방법)
            # 로컬 서버를 통한 직접 열기가 안될 경우를 대비
            pdf_url = f"http://127.0.0.1:8080/{filename}.pdf"
            self.android_webview.loadUrl(pdf_url)

        setup_webview()

    def close_viewer(self):
        if self.android_webview:
            from jnius import autoclass
            from android.runnable import run_on_main_thread
            @run_on_main_thread
            def hide_webview():
                self.android_webview.setVisibility(autoclass('android.view.View').GONE)
            hide_webview()
        self.root.current = 'list'

    def select_source(self, mode):
        content = BoxLayout(orientation='vertical', padding=dp(20), spacing=dp(20))
        pop = Popup(title="파일 출처 선택", content=content, size_hint=(0.85, 0.4))
        def choice(c):
            pop.dismiss()
            if c == 'local': self.open_local_browser(mode)
            else: self.open_smb_shares_browser(mode)
        content.add_widget(Button(text="내 휴대폰", on_release=lambda x: choice('local')))
        content.add_widget(Button(text="PC 공유폴더", on_release=lambda x: choice('smb')))
        pop.open()

    def open_local_browser(self, mode):
        start_p = "/storage/emulated/0" if platform=='android' else os.getcwd()
        if mode == 'file' and self.excel_path and os.path.exists(os.path.dirname(self.excel_path)):
            start_p = os.path.dirname(self.excel_path)
        elif mode == 'dir' and self.pdf_folder_path and os.path.exists(self.pdf_folder_path):
            start_p = self.pdf_folder_path

        fc = FileChooserListView(path=start_p)
        if mode == 'dir': fc.dirselect = True
        
        content = BoxLayout(orientation='vertical', padding=dp(5))
        path_label = Label(text=fc.path, size_hint_y=None, height=dp(40), shorten=True, shorten_from='left')
        fc.bind(path=lambda obj, val: setattr(path_label, 'text', val))
        content.add_widget(path_label); content.add_widget(fc)
        pop = Popup(title="파일/폴더 선택", content=content, size_hint=(0.95, 0.95))
        
        def on_confirm(instance):
            target = fc.selection[0] if fc.selection else fc.path
            if mode == 'file':
                if os.path.isfile(target):
                    self.excel_path = target; self.load_excel_data(target); self.save_settings(); pop.dismiss()
                else: self.show_error_popup("파일을 선택하세요.")
            else:
                if os.path.isdir(target):
                    self.pdf_folder_path = target; self.pdf_source = 'local'; self.save_settings(); pop.dismiss()
                else: self.show_error_popup("폴더가 아닙니다.")

        btn_layout = BoxLayout(size_hint_y=None, height=dp(60), spacing=dp(10))
        btn_layout.add_widget(Button(text="취소", on_release=pop.dismiss))
        btn_layout.add_widget(Button(text="확인", on_release=on_confirm, background_color=(0, 0.7, 0, 1)))
        content.add_widget(btn_layout); pop.open()

    def load_excel_data(self, path):
        try:
            wb = load_workbook(path, data_only=True); ws = wb.active; rows = list(ws.rows)
            headers = [str(cell.value).strip().lower() for cell in rows[0]]
            idx_no, idx_code, idx_qty = headers.index('no'), headers.index('품목코드'), headers.index('수량')
            rv_data = []
            for i, row in enumerate(rows[1:]):
                rv_data.append({
                    'no': str(row[idx_no].value or ''), 'item_code': str(row[idx_code].value or ''), 'quantity': str(row[idx_qty].value or ''),
                    'complete': str(ws.cell(row=i+2, column=headers.index('완료')+1).value or '').upper() == 'V' if '완료' in headers else False,
                    'shortage': str(ws.cell(row=i+2, column=headers.index('수량부족')+1).value or '').upper() == 'V' if '수량부족' in headers else False,
                    'rework': str(ws.cell(row=i+2, column=headers.index('재작업')+1).value or '').upper() == 'V' if '재작업' in headers else False,
                    'real_index': i
                })
            self.root.get_screen('list').ids.rv.data = rv_data
        except: pass

    def sort_by(self, col):
        rv = self.root.get_screen('list').ids.rv
        if not rv.data: return
        new_s = 'desc' if self.sort_states.get(col) == 'asc' else 'asc'
        self.sort_states = {col: new_s}
        for k in ['no','code','qty','comp','short','rew']: setattr(self, f'sort_indicator_{k}', '')
        ind = " ▲" if new_s == 'asc' else " ▼"
        if col == 'no': self.sort_indicator_no = ind
        elif col == 'item_code': self.sort_indicator_code = ind
        elif col == 'quantity': self.sort_indicator_qty = ind
        elif col == 'complete': self.sort_indicator_comp = ind
        elif col == 'shortage': self.sort_indicator_short = ind
        elif col == 'rework': self.sort_indicator_rew = ind
        rv.data = sorted(rv.data, key=lambda x: str(x.get(col, '')).lower(), reverse=(new_s == 'desc'))
        rv.refresh_from_data()

    def update_item_status(self, ic, no, st):
        rv = self.root.get_screen('list').ids.rv
        for d in rv.data:
            if d['item_code'] == ic and d['no'] == no:
                if st == 'complete':
                    d['complete'] = not d['complete']
                    if d['complete']: d['shortage'] = d['rework'] = False
                elif st == 'shortage':
                    d['shortage'] = not d['shortage']
                    if d['shortage']: d['complete'] = d['rework'] = False
                elif st == 'rework':
                    d['rework'] = not d['rework']
                    if d['rework']: d['complete'] = d['shortage'] = False
                break
        rv.refresh_from_data()
        if self.root.current == 'viewer': self.refresh_viewer_ui()

    def refresh_viewer_ui(self):
        item = self.root.get_screen('list').ids.rv.data[self.current_view_idx]
        self.color_comp = [0, 1, 0, 1] if item['complete'] else [0.3, 0.3, 0.3, 1]
        self.color_short = [1, 1, 0, 1] if item['shortage'] else [0.3, 0.3, 0.3, 1]
        self.color_rew = [1, 0, 0, 1] if item['rework'] else [0.3, 0.3, 0.3, 1]

    def update_viewer_status(self, status):
        item = self.root.get_screen('list').ids.rv.data[self.current_view_idx]
        self.update_item_status(item['item_code'], item['no'], status)

    def open_smb_shares_browser(self, mode):
        conn = self.get_smb_conn_only()
        if not conn: self.show_error_popup("SMB 접속 실패"); return
        content = BoxLayout(orientation='vertical'); scroll = ScrollView(); list_box = BoxLayout(orientation='vertical', size_hint_y=None, spacing=dp(5))
        list_box.bind(minimum_height=list_box.setter('height')); scroll.add_widget(list_box)
        pop = Popup(title="공유폴더 선택", content=content, size_hint=(0.95, 0.95))
        try:
            from smb.SMBConnection import SMBConnection
            for s in conn.listShares():
                if s.isSpecial or s.name.endswith('$'): continue
                btn = Button(text=f"📁 {s.name}", size_hint_y=None, height=dp(90))
                btn.bind(on_release=lambda b, s=s: self.open_smb_files_browser(conn, s.name, "/", mode, pop))
                list_box.add_widget(btn)
        except: pass
        content.add_widget(scroll); content.add_widget(Button(text="취소", size_hint_y=None, height=dp(80), on_release=lambda x: (conn.close(), pop.dismiss()))); pop.open()

    def open_smb_files_browser(self, conn, share, path, mode, parent):
        content = BoxLayout(orientation='vertical'); scroll = ScrollView(); list_box = BoxLayout(orientation='vertical', size_hint_y=None, spacing=dp(2))
        list_box.bind(minimum_height=list_box.setter('height')); scroll.add_widget(list_box)
        pop = Popup(title=f"SMB: {share}{path}", content=content, size_hint=(0.95, 0.95))
        def refresh(cp):
            list_box.clear_widgets()
            if cp != "/":
                btn = Button(text=".. 상위폴더", size_hint_y=None, height=dp(80))
                btn.bind(on_release=lambda x: refresh(os.path.dirname(cp.rstrip("/")) or "/")); list_box.add_widget(btn)
            for f in conn.listPath(share, cp):
                if f.filename in ['.', '..']: continue
                btn = Button(text=f"{'📁' if f.isDirectory else '📄'} {f.filename}", size_hint_y=None, height=dp(90))
                btn.bind(on_release=lambda b, f=f: on_click(cp, f)); list_box.add_widget(btn)
        def on_click(cp, f):
            new_p = os.path.join(cp, f.filename).replace("\\", "/")
            if f.isDirectory:
                if mode == 'dir': self.pdf_folder_path = f"{share}{new_p}"; self.pdf_source='smb'; self.save_settings(); pop.dismiss(); parent.dismiss(); conn.close()
                else: refresh(new_p)
            else:
                if mode == 'file':
                    local = os.path.join(LOCAL_BASE, f.filename)
                    with open(local, 'wb') as lf: conn.retrieveFile(share, new_p, lf)
                    self.excel_path = local; self.load_excel_data(local); self.save_settings(); pop.dismiss(); parent.dismiss(); conn.close()
        refresh(path); content.add_widget(scroll); content.add_widget(Button(text="닫기", size_hint_y=None, height=dp(80), on_release=lambda x: pop.dismiss())); pop.open()

    def get_smb_conn_only(self):
        try:
            from smb.SMBConnection import SMBConnection
            ip = self.smb_config['ip']
            conn = SMBConnection(self.smb_config['user'], self.smb_config['pass'], "App", ip, use_ntlm_v2=True, is_direct_tcp=True)
            if conn.connect(ip, 445, timeout=3): return conn
        except: pass
        return None

    def open_smb_settings(self):
        content = BoxLayout(orientation='vertical', padding=20, spacing=10)
        ips = TextInput(text=self.smb_config['ip'], multiline=False, height=dp(60))
        usr = TextInput(text=self.smb_config['user'], multiline=False, height=dp(60))
        pas = TextInput(text=self.smb_config['pass'], password=True, multiline=False, height=dp(60))
        content.add_widget(Label(text="IP")); content.add_widget(ips)
        content.add_widget(Label(text="ID")); content.add_widget(usr)
        content.add_widget(Label(text="PW")); content.add_widget(pas)
        pop = Popup(title="SMB 설정", content=content, size_hint=(0.9, 0.7))
        def save(x): self.smb_config = {'ip':ips.text,'user':usr.text,'pass':pas.text}; self.save_settings(); pop.dismiss()
        content.add_widget(Button(text="저장", on_release=save)); pop.open()

    def save_to_excel(self):
        if not self.excel_path: return
        try:
            wb = load_workbook(self.excel_path); ws = wb.active; headers = [str(c.value).strip().lower() for c in ws[1]]
            cols = {'완료':headers.index('완료')+1 if '완료' in headers else -1, '수량부족':headers.index('수량부족')+1 if '수량부족' in headers else -1, '재작업':headers.index('재작업')+1 if '재작업' in headers else -1}
            for d in self.root.get_screen('list').ids.rv.data:
                r = d['real_index']+2
                if cols['완료']>0: ws.cell(row=r, column=cols['완료']).value = 'V' if d['complete'] else ''
                if cols['수량부족']>0: ws.cell(row=r, column=cols['수량부족']).value = 'V' if d['shortage'] else ''
                if cols['재작업']>0: ws.cell(row=r, column=cols['재작업']).value = 'V' if d['rework'] else ''
            wb.save(self.excel_path); self.show_error_popup("저장 완료")
        except: self.show_error_popup("저장 실패")

    def load_settings(self):
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, 'r', encoding='utf-8') as f:
                    d = json.load(f); self.excel_path = d.get('excel_path', ''); self.pdf_folder_path = d.get('pdf_folder_path', '')
                    self.pdf_source = d.get('pdf_source', 'local'); self.smb_config = d.get('smb_config', {'ip':'','user':'','pass':''})
            except: pass

    def save_settings(self):
        with open(SETTINGS_FILE, 'w', encoding='utf-8') as f:
            json.dump({'excel_path': self.excel_path, 'pdf_folder_path': self.pdf_folder_path, 'pdf_source': self.pdf_source, 'smb_config': self.smb_config}, f, ensure_ascii=False)

    def show_error_popup(self, msg): Popup(title="알림", content=Label(text=msg), size_hint=(0.8, 0.4)).open()

if __name__ == '__main__':
    CheckSheetApp().run()
