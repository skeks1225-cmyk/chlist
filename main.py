import os
import json
import traceback
import subprocess
import socket
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
from kivy.uix.scatterlayout import ScatterLayout
from kivy.core.text import LabelBase
from kivy.utils import platform
from kivy.clock import Clock
from kivy.metrics import dp

# --- 1. 한글 폰트 전역 등록 ---
FONT_NAME = "font.ttf"
if platform == 'android':
    FONT_NAME = os.path.join(os.path.dirname(__file__), "font.ttf")

if os.path.exists(FONT_NAME):
    try:
        LabelBase.register(name="Roboto", fn_regular=FONT_NAME)
        LabelBase.register(name="Korean", fn_regular=FONT_NAME)
        from kivy.core.text import Label as CoreLabel
        CoreLabel.register("Roboto", FONT_NAME)
    except: pass

# --- 2. 모든 위젯 스타일 설정 ---
KV_UI = """
<Label>:
    font_name: 'Roboto'
<Button>:
    font_name: 'Roboto'
<TextInput>:
    font_name: 'Roboto'
<FileChooserLabel>:
    font_name: 'Roboto'
<Popup>:
    title_font: 'Roboto'

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
                bold: True
            Button:
                text: '닫기'
                size_hint_x: None
                width: dp(100)
                on_release: app.close_viewer()

        # 고해상도 도면 뷰어 영역 (확대/축소 지원)
        ScatterLayout:
            id: scatter
            do_rotation: False
            auto_bring_to_front: False
            Image:
                id: pdf_img
                source: app.viewer_image_source
                allow_stretch: True
                keep_ratio: True
                size: self.parent.size
                pos: 0, 0

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
if not os.path.exists(LOCAL_BASE): os.makedirs(LOCAL_BASE)

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

class CheckSheetApp(App):
    excel_path = StringProperty(''); pdf_folder_path = StringProperty('')
    pdf_source = StringProperty('local'); smb_config = DictProperty({'ip': '', 'user': '', 'pass': ''})
    sort_indicator_no = StringProperty(''); sort_indicator_code = StringProperty(''); sort_indicator_qty = StringProperty('')
    sort_indicator_comp = StringProperty(''); sort_indicator_short = StringProperty(''); sort_indicator_rew = StringProperty('')
    sort_states = {}
    viewer_title = StringProperty(''); viewer_image_source = StringProperty('')
    current_view_idx = NumericProperty(-1)
    color_comp = ListProperty([0.3, 0.3, 0.3, 1]); color_short = ListProperty([0.3, 0.3, 0.3, 1]); color_rew = ListProperty([0.3, 0.3, 0.3, 1])
    touch_start_x = 0

    def build(self):
        self.load_settings()
        # 외부 kv 파일을 무시하기 위해 빈 파일로 취급하거나 이름을 다르게 설정
        self.title = "CheckSheet Pro"
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
                    uri = autoclass('android.net.Uri').fromParts("package", Context.getPackageName(), None)
                    intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                    intent.setData(uri); Context.startActivity(intent)
        except: pass

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
        # 마지막 폴더 기억
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

    def open_pdf_viewer(self, idx):
        self.current_view_idx = idx; self.root.current = 'viewer'
        # 뷰어 진입 시 줌 초기화
        self.root.get_screen('viewer').ids.scatter.scale = 1
        self.root.get_screen('viewer').ids.scatter.pos = (0, 0)
        self.load_viewer_pdf()

    def close_viewer(self): self.root.current = 'list'
    
    def load_viewer_pdf(self):
        item = self.root.get_screen('list').ids.rv.data[self.current_view_idx]
        self.viewer_title = item['item_code']; self.refresh_viewer_ui()
        base_path = self.pdf_folder_path if self.pdf_folder_path else LOCAL_BASE
        local_path = os.path.join(base_path, f"{self.viewer_title}.pdf")
        if not os.path.exists(local_path):
            self.show_error_popup(f"파일 없음: {self.viewer_title}.pdf")
            return
        if platform == 'android': self.render_pdf(local_path)
        else: self.viewer_image_source = ""

    def refresh_viewer_ui(self):
        item = self.root.get_screen('list').ids.rv.data[self.current_view_idx]
        self.color_comp = [0, 1, 0, 1] if item['complete'] else [0.3, 0.3, 0.3, 1]
        self.color_short = [1, 1, 0, 1] if item['shortage'] else [0.3, 0.3, 0.3, 1]
        self.color_rew = [1, 0, 0, 1] if item['rework'] else [0.3, 0.3, 0.3, 1]

    def update_viewer_status(self, status):
        item = self.root.get_screen('list').ids.rv.data[self.current_view_idx]
        self.update_item_status(item['item_code'], item['no'], status)

    def render_pdf(self, path):
        try:
            from jnius import autoclass
            f = autoclass('java.io.File')(path)
            if not f.exists(): return
            pfd = autoclass('android.os.ParcelFileDescriptor').open(f, autoclass('android.os.ParcelFileDescriptor').MODE_READ_ONLY)
            renderer = autoclass('android.graphics.pdf.PdfRenderer')(pfd); page = renderer.openPage(0)
            # 도면 확인을 위해 4배 고해상도 렌더링 (벡터급 화질 구현)
            bw, bh = int(page.getWidth() * 4), int(page.getHeight() * 4)
            bitmap = autoclass('android.graphics.Bitmap').createBitmap(bw, bh, autoclass('android.graphics.Bitmap$Config').ARGB_8888)
            page.render(bitmap, None, None, page.RENDER_MODE_FOR_DISPLAY)
            tmp = os.path.join(self.user_data_dir, "view.png")
            out = autoclass('java.io.FileOutputStream')(tmp)
            bitmap.compress(autoclass('android.graphics.Bitmap$CompressFormat').PNG, 100, out); out.close()
            page.close(); renderer.close(); self.viewer_image_source = ""; self.viewer_image_source = tmp
        except: pass

    def on_viewer_touch_down(self, t):
        self.touch_start_x = t.x

    def on_viewer_touch_up(self, t):
        # 확대 중(scale > 1.1)일 때는 슬라이드 기능을 막아 도면 이동을 방해하지 않음
        if self.root.get_screen('viewer').ids.scatter.scale > 1.1: return
        dx = t.x - self.touch_start_x
        if abs(dx) > dp(150):
            rv_data = self.root.get_screen('list').ids.rv.data
            if dx > 0 and self.current_view_idx > 0: 
                self.current_view_idx -= 1; self.load_viewer_pdf()
            elif dx < 0 and self.current_view_idx < len(rv_data)-1: 
                self.current_view_idx += 1; self.load_viewer_pdf()

    def open_smb_shares_browser(self, mode):
        conn = self.get_smb_conn_only()
        if not conn: self.show_error_popup("SMB 접속 실패"); return
        content = BoxLayout(orientation='vertical'); scroll = ScrollView(); list_box = BoxLayout(orientation='vertical', size_hint_y=None, spacing=dp(5))
        list_box.bind(minimum_height=list_box.setter('height')); scroll.add_widget(list_box)
        pop = Popup(title="공유폴더 선택", content=content, size_hint=(0.95, 0.95))
        try:
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
