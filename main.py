import os
import json
import shutil
import traceback

from kivy.app import App
from kivy.lang import Builder
from kivy.utils import platform
from kivy.clock import Clock
from kivy.properties import StringProperty, BooleanProperty, NumericProperty, DictProperty, ListProperty
from kivy.metrics import dp
from kivy.uix.screenmanager import ScreenManager, Screen
from kivy.uix.recycleview import RecycleView
from kivy.uix.boxlayout import BoxLayout

# --- 1. UI 클래스 정의 ---
class ListScreen(Screen): pass
class ViewerScreen(Screen): pass # 화면은 유지하되 내용은 비움
class CheckSheetRV(RecycleView): pass

class RowWidget(BoxLayout):
    no = StringProperty(''); item_code = StringProperty(''); quantity = StringProperty('')
    complete = BooleanProperty(False); shortage = BooleanProperty(False); rework = BooleanProperty(False)
    def on_checkbox_active(self, ct): App.get_running_app().update_item_status(self.item_code, self.no, ct)
    def open_pdf(self): 
        # WebView 테스트 전까지는 작동 중지
        Popup(title="알림", content=Label(text="WebView Test skipped in this step"), size_hint=(0.6, 0.3)).open()

# --- 2. UI 디자인 ---
KV_UI = """
<Label>:
    font_name: 'Roboto'
<Button>:
    font_name: 'Roboto'

<ListScreen>:
    BoxLayout:
        orientation: 'vertical'
        BoxLayout:
            size_hint_y: None
            height: '40dp'
            Label:
                text: "현재 파일: " + app.current_filename
                bold: True
        BoxLayout:
            size_hint_y: None
            height: '60dp'
            padding: '5dp'
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
                on_release: app.save_to_excel()
        CheckSheetRV:
            id: rv
            viewclass: 'RowWidget'
            RecycleBoxLayout:
                default_size: None, dp(60)
                default_size_hint: 1, None
                size_hint_y: None
                height: self.minimum_height
                orientation: 'vertical'

<RowWidget>:
    orientation: 'horizontal'
    Label: text: root.no; size_hint_x: 0.1
    Button:
        text: root.item_code; size_hint_x: 0.3
        on_release: root.open_pdf()
    Label: text: root.quantity; size_hint_x: 0.15
    Button:
        text: 'V' if root.complete else ''; size_hint_x: 0.15
        on_release: root.on_checkbox_active('complete')
    Button:
        text: 'V' if root.shortage else ''; size_hint_x: 0.15
        on_release: root.on_checkbox_active('shortage')
    Button:
        text: 'V' if root.rework else ''; size_hint_x: 0.15
        on_release: root.on_checkbox_active('rework')
"""

SETTINGS_FILE = 'settings.json'
LOCAL_BASE = "/sdcard/Download/CheckSheet" if platform == 'android' else os.path.join(os.getcwd(), "CheckSheet_Data")

class CheckSheetApp(App):
    excel_path = StringProperty(''); pdf_folder_path = StringProperty('')
    current_filename = StringProperty('파일을 선택하세요')
    smb_config = DictProperty({'ip': '', 'user': '', 'pass': ''})
    sort_indicator_no = StringProperty(''); sort_indicator_code = StringProperty(''); sort_indicator_qty = StringProperty('')
    sort_indicator_comp = StringProperty(''); sort_indicator_short = StringProperty(''); sort_indicator_rew = StringProperty('')
    sort_states = {}; current_view_idx = NumericProperty(-1)
    color_comp = ListProperty([0.3, 0.3, 0.3, 1]); color_short = ListProperty([0.3, 0.3, 0.3, 1]); color_rew = ListProperty([0.3, 0.3, 0.3, 1])

    def build(self):
        # 폰트 등록 (최소화)
        if platform == 'android':
            try:
                from kivy.core.text import LabelBase
                font_path = os.path.join(os.path.dirname(__file__), "font.ttf")
                if os.path.exists(font_path):
                    LabelBase.register(name="Roboto", fn_regular=font_path)
            except: pass
        self.load_settings()
        Builder.load_string(KV_UI)
        sm = ScreenManager()
        sm.add_widget(ListScreen(name='list'))
        return sm

    # 기능 복구: 엑셀 로드/저장, SMB (WebView 관련 제외)
    def load_excel_data(self, path):
        try:
            from openpyxl import load_workbook
            wb = load_workbook(path, data_only=True); ws = wb.active; rows = list(ws.rows)
            h = [str(c.value).strip().lower() if c.value else "" for c in rows[0]]
            idx_no, idx_code, idx_qty = h.index('no'), h.index('품목코드'), h.index('수량')
            rv_data = []
            for i, row in enumerate(rows[1:]):
                if not row[idx_code].value: continue
                rv_data.append({
                    'no': str(row[idx_no].value or ''), 'item_code': str(row[idx_code].value or ''), 'quantity': str(row[idx_qty].value or ''),
                    'complete': str(ws.cell(row=i+2, column=h.index('완료')+1).value or '').upper() == 'V' if '완료' in h else False,
                    'shortage': str(ws.cell(row=i+2, column=h.index('수량부족')+1).value or '').upper() == 'V' if '수량부족' in h else False,
                    'rework': str(ws.cell(row=i+2, column=h.index('재작업')+1).value or '').upper() == 'V' if '재작업' in h else False,
                    'real_index': i
                })
            self.root.get_screen('list').ids.rv.data = rv_data
            self.current_filename = os.path.basename(path)
        except: pass

    def save_to_excel(self):
        if not self.excel_path: return
        try:
            from openpyxl import load_workbook
            wb = load_workbook(self.excel_path); ws = wb.active; h = [str(c.value).strip() if c.value else "" for c in ws[1]]
            target = ['완료', '수량부족', '재작업']; cols = {}
            for n in target:
                if n in h: cols[n] = h.index(n) + 1
                else:
                    new = len(h) + 1; ws.cell(row=1, column=new).value = n; cols[n] = new; h.append(n)
            for d in self.root.get_screen('list').ids.rv.data:
                r = d['real_index'] + 2
                ws.cell(row=r, column=cols['완료']).value = 'V' if d.get('complete') else ''
                ws.cell(row=r, column=cols['수량부족']).value = 'V' if d.get('shortage') else ''
                ws.cell(row=r, column=cols['재작업']).value = 'V' if d.get('rework') else ''
            wb.save(self.excel_path)
        except: pass

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

    def select_source(self, mode):
        from kivy.uix.label import Label # 명시적 로드
        from kivy.uix.button import Button
        content = BoxLayout(orientation='vertical', padding=20, spacing=20)
        pop = Popup(title="선택", content=content, size_hint=(0.8, 0.4))
        content.add_widget(Button(text="휴대폰", on_release=lambda x: (pop.dismiss(), self.open_local_browser(mode))))
        content.add_widget(Button(text="SMB", on_release=lambda x: (pop.dismiss(), self.open_smb_shares_browser(mode))))
        pop.open()

    def open_local_browser(self, mode):
        from kivy.uix.filechooser import FileChooserListView
        start_p = "/storage/emulated/0" if platform=='android' else os.getcwd()
        fc = FileChooserListView(path=start_p)
        if mode == 'dir': fc.dirselect = True
        content = BoxLayout(orientation='vertical', padding=5); pl = Label(text=fc.path, size_hint_y=None, height=40)
        fc.bind(path=lambda obj, val: setattr(pl, 'text', val)); content.add_widget(pl); content.add_widget(fc)
        pop = Popup(title="파일 선택", content=content, size_hint=(0.9, 0.9))
        def confirm(x):
            t = fc.selection[0] if fc.selection else fc.path
            if mode == 'file' and os.path.isfile(t): self.excel_path = t; self.load_excel_data(t); self.save_settings(); pop.dismiss()
            elif mode == 'dir' and os.path.isdir(t): self.pdf_folder_path = t; self.save_settings(); pop.dismiss()
        content.add_widget(Button(text="확인", size_hint_y=None, height=60, on_release=confirm)); pop.open()

    def open_smb_shares_browser(self, mode):
        conn = self.get_smb_conn_only()
        if not conn: return
        content = BoxLayout(orientation='vertical'); lb = BoxLayout(orientation='vertical', size_hint_y=None); lb.bind(minimum_height=lb.setter('height'))
        scroll = ScrollView(); scroll.add_widget(lb)
        pop = Popup(title="공유폴더", content=content, size_hint=(0.9, 0.9))
        for s in conn.listShares():
            if s.isSpecial or s.name.endswith('$'): continue
            b = Button(text=s.name, size_hint_y=None, height=80); b.bind(on_release=lambda x, n=s.name: self.open_smb_files_browser(conn, n, "/", mode, pop)); lb.add_widget(b)
        content.add_widget(scroll); pop.open()

    def open_smb_files_browser(self, conn, share, path, mode, parent):
        content = BoxLayout(orientation='vertical'); lb = BoxLayout(orientation='vertical', size_hint_y=None); lb.bind(minimum_height=lb.setter('height'))
        scroll = ScrollView(); scroll.add_widget(lb)
        pop = Popup(title=f"SMB: {share}", content=content, size_hint=(0.9, 0.9))
        for f in conn.listPath(share, path):
            if f.filename in ['.', '..']: continue
            b = Button(text=f.filename, size_hint_y=None, height=80)
            def click(x, file=f):
                np = os.path.join(path, file.filename).replace("\\", "/")
                if file.isDirectory: self.open_smb_files_browser(conn, share, np, mode, parent)
                elif mode == 'file':
                    local = os.path.join(LOCAL_BASE, file.filename)
                    if not os.path.exists(LOCAL_BASE): os.makedirs(LOCAL_BASE)
                    with open(local, 'wb') as lf: conn.retrieveFile(share, np, lf)
                    self.excel_path = local; self.load_excel_data(local); self.save_settings(); pop.dismiss(); parent.dismiss()
            b.bind(on_release=click); lb.add_widget(b)
        content.add_widget(scroll); pop.open()

    def get_smb_conn_only(self):
        try:
            from smb.SMBConnection import SMBConnection
            c = self.smb_config; conn = SMBConnection(c['user'], c['pass'], "App", c['ip'], use_ntlm_v2=True, is_direct_tcp=True)
            if conn.connect(c['ip'], 445, timeout=3): return conn
        except: return None

    def open_smb_settings(self):
        content = BoxLayout(orientation='vertical', padding=10); ips = TextInput(text=self.smb_config['ip']); usr = TextInput(text=self.smb_config['user']); pas = TextInput(text=self.smb_config['pass'], password=True)
        content.add_widget(Label(text="IP")); content.add_widget(ips); content.add_widget(Label(text="ID")); content.add_widget(usr); content.add_widget(Label(text="PW")); content.add_widget(pas)
        pop = Popup(title="SMB 설정", content=content, size_hint=(0.8, 0.6))
        def save(x): self.smb_config = {'ip':ips.text,'user':usr.text,'pass':pas.text}; self.save_settings(); pop.dismiss()
        content.add_widget(Button(text="저장", on_release=save)); pop.open()

    def load_settings(self):
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, 'r') as f:
                    d = json.load(f); self.excel_path = d.get('excel_path', ''); self.pdf_folder_path = d.get('pdf_folder_path', ''); self.smb_config = d.get('smb_config', {'ip':'','user':'','pass':''})
            except: pass

    def save_settings(self):
        with open(SETTINGS_FILE, 'w') as f: json.dump({'excel_path': self.excel_path, 'pdf_folder_path': self.pdf_folder_path, 'smb_config': self.smb_config}, f)

if __name__ == '__main__':
    CheckSheetApp().run()
