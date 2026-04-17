import os
import json
import shutil
import traceback
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
    except: pass

# --- 2. UI 디자인 ---
KV_UI = """
<Label>:
    font_name: 'Roboto'
<Button>:
    font_name: 'Roboto'
<TextInput>:
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
            height: '40dp'
            canvas.before:
                Color:
                    rgba: 0.15, 0.3, 0.4, 1
                Rectangle:
                    pos: self.pos
                    size: self.size
            Label:
                text: "현재 파일: " + app.current_filename
                bold: True

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
            height: dp(50)
            padding: dp(5)
            spacing: dp(10)
            canvas.before:
                Color:
                    rgba: 0.2, 0.2, 0.2, 1
                Rectangle:
                    pos: self.pos
                    size: self.size
            Button:
                text: '닫기'
                size_hint_x: None
                width: dp(80)
                on_release: app.close_webview_pdf()
            Label:
                text: app.viewer_title
                bold: True
                font_size: '14sp'

        Widget:
            id: webview_placeholder

        BoxLayout:
            size_hint_y: None
            height: dp(50)
            spacing: dp(2)
            Button:
                text: '<<< 이전'
                background_color: 0.2, 0.3, 0.5, 1
                on_release: app.navigate_pdf(-1)
            Button:
                text: '다음 >>>'
                background_color: 0.2, 0.3, 0.5, 1
                on_release: app.navigate_pdf(1)

        BoxLayout:
            size_hint_y: None
            height: dp(70)
            spacing: dp(5)
            padding: dp(5)
            canvas.before:
                Color:
                    rgba: 0.1, 0.1, 0.1, 1
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
    Label: text: root.no; size_hint_x: 0.1
    Button:
        text: root.item_code; size_hint_x: 0.3
        background_normal: ''; background_color: 0.2, 0.4, 0.6, 1
        on_release: root.open_pdf()
    Label: text: root.quantity; size_hint_x: 0.15
    Button:
        text: 'V' if root.complete else ''; size_hint_x: 0.15
        background_normal: ''; background_color: (0, 1, 0, 0.5) if root.complete else (0.3, 0.3, 0.3, 1)
        on_release: root.on_checkbox_active('complete')
    Button:
        text: 'V' if root.shortage else ''; size_hint_x: 0.15
        background_normal: ''; background_color: (1, 1, 0, 0.5) if root.shortage else (0.3, 0.3, 0.3, 1)
        on_release: root.on_checkbox_active('shortage')
    Button:
        text: 'V' if root.rework else ''; size_hint_x: 0.15
        background_normal: ''; background_color: (1, 0, 0, 0.5) if root.rework else (0.3, 0.3, 0.3, 1)
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
    def open_pdf(self): App.get_running_app().prepare_and_open_pdf(self.item_code)

class CheckSheetApp(App):
    excel_path = StringProperty(''); pdf_folder_path = StringProperty('')
    current_filename = StringProperty('파일을 선택하세요')
    pdf_source = StringProperty('local'); smb_config = DictProperty({'ip': '', 'user': '', 'pass': ''})
    sort_indicator_no = StringProperty(''); sort_indicator_code = StringProperty(''); sort_indicator_qty = StringProperty('')
    sort_indicator_comp = StringProperty(''); sort_indicator_short = StringProperty(''); sort_indicator_rew = StringProperty('')
    sort_states = {}
    viewer_title = StringProperty('')
    current_view_idx = NumericProperty(-1)
    color_comp = ListProperty([0.3, 0.3, 0.3, 1]); color_short = ListProperty([0.3, 0.3, 0.3, 1]); color_rew = ListProperty([0.3, 0.3, 0.3, 1])
    
    webview = None
    data_loaded = False

    def build(self):
        self.load_settings()
        Builder.load_string(KV_UI)
        sm = ScreenManager()
        sm.add_widget(ListScreen(name='list'))
        sm.add_widget(ViewerScreen(name='viewer'))
        return sm

    def on_start(self):
        if platform == 'android': 
            Clock.schedule_once(self.ask_permissions, 1)
        if not self.data_loaded and self.excel_path and os.path.exists(self.excel_path):
            self.load_excel_data(self.excel_path)
            self.data_loaded = True

    def ask_permissions(self, dt):
        try:
            from android.permissions import request_permissions, Permission
            from jnius import autoclass
            request_permissions([Permission.READ_EXTERNAL_STORAGE, Permission.WRITE_EXTERNAL_STORAGE, Permission.INTERNET, Permission.ACCESS_NETWORK_STATE])
            Env = autoclass('android.os.Environment')
            if hasattr(Env, 'isExternalStorageManager'):
                if not Env.isExternalStorageManager():
                    mActivity = autoclass('org.kivy.android.PythonActivity').mActivity
                    intent = autoclass('android.content.Intent')(autoclass('android.provider.Settings').ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                    intent.setData(autoclass('android.net.Uri').fromParts("package", mActivity.getPackageName(), None))
                    mActivity.startActivity(intent)
        except: pass

    # --- [핵심] PDF 준비 및 WebView 실행 ---
    def prepare_and_open_pdf(self, item_code):
        rv_data = self.root.get_screen('list').ids.rv.data
        for i, d in enumerate(rv_data):
            if d['item_code'] == item_code:
                self.current_view_idx = i; break
        self.load_pdf_into_cache(item_code)

    def load_pdf_into_cache(self, item_code):
        """지정된 item_code의 PDF를 temp.pdf로 복사하고 WebView 로드"""
        self.viewer_title = f"[{self.current_view_idx + 1}] {item_code}.pdf"
        base_path = self.pdf_folder_path if self.pdf_folder_path else LOCAL_BASE
        src_path = os.path.join(base_path, f"{item_code}.pdf")
        
        if not os.path.exists(src_path):
            self.show_error_popup(f"파일 없음: {item_code}.pdf"); return

        try:
            from jnius import autoclass
            mActivity = autoclass('org.kivy.android.PythonActivity').mActivity
            internal_dir = mActivity.getFilesDir().getAbsolutePath()
            dest_path = os.path.join(internal_dir, "temp.pdf")
            
            if os.path.exists(dest_path): os.remove(dest_path)
            shutil.copy2(src_path, dest_path)
            
            self.root.current = 'viewer'
            self.refresh_viewer_ui()
            
            if platform == 'android':
                Clock.schedule_once(lambda dt: self.show_android_webview(dest_path), 0.2)
        except Exception as e:
            self.show_error_popup(f"PDF 준비 실패: {e}")

    def show_android_webview(self, pdf_path):
        from jnius import autoclass
        from android.runnable import run_on_main_thread
        @run_on_main_thread
        def _setup():
            try:
                mActivity = autoclass('org.kivy.android.PythonActivity').mActivity
                if not self.webview:
                    self.webview = autoclass('android.webkit.WebView')(mActivity)
                    settings = self.webview.getSettings()
                    settings.setJavaScriptEnabled(True)
                    settings.setAllowFileAccess(True)
                    settings.setDomStorageEnabled(True)
                    settings.setBuiltInZoomControls(True)
                    settings.setDisplayZoomControls(False)
                    mActivity.addContentView(self.webview, autoclass('android.view.ViewGroup$LayoutParams')(-1, -1))
                self.webview.setVisibility(0)
                self.webview.bringToFront()
                url = f"file:///android_asset/pdfjs/web/viewer.html?file=file://{pdf_path}"
                self.webview.loadUrl(url)
            except Exception as e: print(f"WebView Error: {e}")
        _setup()

    def navigate_pdf(self, direction):
        rv_data = self.root.get_screen('list').ids.rv.data
        if not rv_data: return
        new_idx = self.current_view_idx + direction
        if 0 <= new_idx < len(rv_data):
            self.current_view_idx = new_idx
            self.load_pdf_into_cache(rv_data[new_idx]['item_code'])
        else:
            self.show_error_popup("항목의 끝입니다.")

    def close_webview_pdf(self):
        if platform == 'android' and self.webview:
            from android.runnable import run_on_main_thread
            @run_on_main_thread
            def _hide(): self.webview.setVisibility(8)
            _hide()
        self.root.current = 'list'

    # --- 데이터 로직 ---
    def load_excel_data(self, path):
        try:
            wb = load_workbook(path, data_only=True); ws = wb.active; rows = list(ws.rows)
            if not rows: return
            headers = [str(cell.value).strip().lower() if cell.value else "" for cell in rows[0]]
            try:
                idx_no, idx_code, idx_qty = headers.index('no'), headers.index('품목코드'), headers.index('수량')
            except ValueError:
                self.show_error_popup("엑셀 헤더 확인 필요(no, 품목코드, 수량)"); return
            rv_data = []
            for i, row in enumerate(rows[1:]):
                if not row[idx_code].value: continue
                rv_data.append({
                    'no': str(row[idx_no].value or ''), 'item_code': str(row[idx_code].value or ''), 'quantity': str(row[idx_qty].value or ''),
                    'complete': str(ws.cell(row=i+2, column=headers.index('완료')+1).value or '').upper() == 'V' if '완료' in headers else False,
                    'shortage': str(ws.cell(row=i+2, column=headers.index('수량부족')+1).value or '').upper() == 'V' if '수량부족' in headers else False,
                    'rework': str(ws.cell(row=i+2, column=headers.index('재작업')+1).value or '').upper() == 'V' if '재작업' in headers else False,
                    'real_index': i
                })
            self.root.get_screen('list').ids.rv.data = rv_data; self.data_loaded = True
            self.current_filename = os.path.basename(path)
        except Exception as e: self.show_error_popup(f"엑셀 로드 실패: {e}")

    def save_to_excel(self):
        if not self.excel_path: return
        try:
            wb = load_workbook(self.excel_path); ws = wb.active; headers = [str(c.value).strip() if c.value else "" for c in ws[1]]
            target_cols = ['완료', '수량부족', '재작업']; cols = {}
            for col_name in target_cols:
                if col_name in headers: cols[col_name] = headers.index(col_name) + 1
                else:
                    new_idx = len(headers) + 1; ws.cell(row=1, column=new_idx).value = col_name
                    cols[col_name] = new_idx; headers.append(col_name)
            for d in self.root.get_screen('list').ids.rv.data:
                r = d['real_index'] + 2
                ws.cell(row=r, column=cols['완료']).value = 'V' if d.get('complete') else ''
                ws.cell(row=r, column=cols['수량부족']).value = 'V' if d.get('shortage') else ''
                ws.cell(row=r, column=cols['재작업']).value = 'V' if d.get('rework') else ''
            wb.save(self.excel_path); self.show_error_popup("저장 완료")
        except Exception as e: self.show_error_popup(f"저장 실패: {e}")

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
        def sort_key(x):
            val = str(x.get(col, '')).lower()
            if col in ['no', 'quantity']:
                try: return int(''.join(filter(str.isdigit, val)) or 0)
                except: return val
            return val
        rv.data = sorted(rv.data, key=sort_key, reverse=(new_s == 'desc'))
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
        fc = FileChooserListView(path=start_p)
        if mode == 'dir': fc.dirselect = True
        content = BoxLayout(orientation='vertical', padding=dp(5)); path_label = Label(text=fc.path, size_hint_y=None, height=dp(40), shorten=True, shorten_from='left')
        fc.bind(path=lambda obj, val: setattr(path_label, 'text', val)); content.add_widget(path_label); content.add_widget(fc)
        pop = Popup(title="선택", content=content, size_hint=(0.95, 0.95))
        def on_confirm(instance):
            target = fc.selection[0] if fc.selection else fc.path
            if mode == 'file':
                if os.path.isfile(target): self.excel_path = target; self.data_loaded = False; self.load_excel_data(target); self.save_settings(); pop.dismiss()
                else: self.show_error_popup("파일을 선택하세요.")
            else:
                if os.path.isdir(target): self.pdf_folder_path = target; self.pdf_source = 'local'; self.save_settings(); pop.dismiss()
                else: self.show_error_popup("폴더가 아닙니다.")
        btn_layout = BoxLayout(size_hint_y=None, height=dp(60), spacing=dp(10))
        btn_layout.add_widget(Button(text="취소", on_release=pop.dismiss)); btn_layout.add_widget(Button(text="확인", on_release=on_confirm, background_color=(0, 0.7, 0, 1))); content.add_widget(btn_layout); pop.open()

    def open_smb_shares_browser(self, mode):
        conn = self.get_smb_conn_only()
        if not conn: self.show_error_popup("SMB 접속 실패"); return
        content = BoxLayout(orientation='vertical'); scroll = ScrollView(); list_box = BoxLayout(orientation='vertical', size_hint_y=None, spacing=dp(5))
        list_box.bind(minimum_height=list_box.setter('height')); scroll.add_widget(list_box)
        pop = Popup(title="공유폴더 선택", content=content, size_hint=(0.95, 0.95))
        try:
            for s in conn.listShares():
                if s.isSpecial or s.name.endswith('$'): continue
                btn = Button(text=f"📁 {s.name}", size_hint_y=None, height=dp(90)); btn.bind(on_release=lambda b, s=s: self.open_smb_files_browser(conn, s.name, "/", mode, pop)); list_box.add_widget(btn)
        except: pass
        content.add_widget(scroll); content.add_widget(Button(text="취소", size_hint_y=None, height=dp(80), on_release=lambda x: (conn.close(), pop.dismiss()))); pop.open()

    def open_smb_files_browser(self, conn, share, path, mode, parent):
        content = BoxLayout(orientation='vertical'); scroll = ScrollView(); list_box = BoxLayout(orientation='vertical', size_hint_y=None, spacing=dp(2))
        list_box.bind(minimum_height=list_box.setter('height')); scroll.add_widget(list_box)
        pop = Popup(title=f"SMB: {share}{path}", content=content, size_hint=(0.95, 0.95))
        def refresh(cp):
            list_box.clear_widgets()
            if cp != "/":
                btn = Button(text=".. 상위폴더", size_hint_y=None, height=dp(80)); btn.bind(on_release=lambda x: refresh(os.path.dirname(cp.rstrip("/")) or "/")); list_box.add_widget(btn)
            for f in conn.listPath(share, cp):
                if f.filename in ['.', '..']: continue
                btn = Button(text=f"{'📁' if f.isDirectory else '📄'} {f.filename}", size_hint_y=None, height=dp(90)); btn.bind(on_release=lambda b, f=f: on_click(cp, f)); list_box.add_widget(btn)
        def on_click(cp, f):
            new_p = os.path.join(cp, f.filename).replace("\\", "/")
            if f.isDirectory:
                if mode == 'dir': self.pdf_folder_path = f"{share}{new_p}"; self.pdf_source='smb'; self.save_settings(); pop.dismiss(); parent.dismiss(); conn.close()
                else: refresh(new_p)
            else:
                if mode == 'file':
                    local = os.path.join(LOCAL_BASE, f.filename)
                    if not os.path.exists(LOCAL_BASE): os.makedirs(LOCAL_BASE)
                    with open(local, 'wb') as lf: conn.retrieveFile(share, new_p, lf)
                    self.excel_path = local; self.load_excel_data(local); self.save_settings(); pop.dismiss(); parent.dismiss(); conn.close()
        refresh(path); content.add_widget(scroll); content.add_widget(Button(text="닫기", size_hint_y=None, height=dp(80), on_release=lambda x: pop.dismiss())); pop.open()

    def get_smb_conn_only(self):
        try:
            from smb.SMBConnection import SMBConnection
            ip = self.smb_config['ip']; conn = SMBConnection(self.smb_config['user'], self.smb_config['pass'], "App", ip, use_ntlm_v2=True, is_direct_tcp=True)
            if conn.connect(ip, 445, timeout=3): return conn
        except: pass
        return None

    def open_smb_settings(self):
        content = BoxLayout(orientation='vertical', padding=20, spacing=10)
        ips = TextInput(text=self.smb_config['ip'], multiline=False, height=dp(60)); usr = TextInput(text=self.smb_config['user'], multiline=False, height=dp(60)); pas = TextInput(text=self.smb_config['pass'], password=True, multiline=False, height=dp(60))
        content.add_widget(Label(text="IP")); content.add_widget(ips); content.add_widget(Label(text="ID")); content.add_widget(usr); content.add_widget(Label(text="PW")); content.add_widget(pas)
        pop = Popup(title="SMB 설정", content=content, size_hint=(0.9, 0.7))
        def save(x): self.smb_config = {'ip':ips.text,'user':usr.text,'pass':pas.text}; self.save_settings(); pop.dismiss()
        content.add_widget(Button(text="저장", on_release=save)); pop.open()

    def load_settings(self):
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, 'r', encoding='utf-8') as f:
                    d = json.load(f); self.excel_path = d.get('excel_path', ''); self.pdf_folder_path = d.get('pdf_folder_path', ''); self.pdf_source = d.get('pdf_source', 'local'); self.smb_config = d.get('smb_config', {'ip':'','user':'','pass':''})
            except: pass

    def save_settings(self):
        with open(SETTINGS_FILE, 'w', encoding='utf-8') as f: json.dump({'excel_path': self.excel_path, 'pdf_folder_path': self.pdf_folder_path, 'pdf_source': self.pdf_source, 'smb_config': self.smb_config}, f, ensure_ascii=False)

    def show_error_popup(self, msg): Popup(title="알림", content=Label(text=msg), size_hint=(0.8, 0.4)).open()

if __name__ == '__main__':
    CheckSheetApp().run()
