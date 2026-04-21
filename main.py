import os
import json
import shutil
import traceback
import re

from kivy.app import App
from kivy.lang import Builder
from kivy.utils import platform
from kivy.clock import Clock
from kivy.properties import StringProperty, BooleanProperty, NumericProperty, DictProperty, ListProperty
from kivy.metrics import dp
from kivy.uix.screenmanager import ScreenManager, Screen
from kivy.uix.recycleview import RecycleView
from kivy.uix.recycleboxlayout import RecycleBoxLayout
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.uix.button import Button
from kivy.uix.popup import Popup
from kivy.uix.filechooser import FileChooserListView
from kivy.uix.scrollview import ScrollView
from kivy.uix.textinput import TextInput
from kivy.core.text import LabelBase

# --- 폰트 등록 ---
if os.path.exists("font.ttf"):
    try: LabelBase.register(name="Roboto", fn_regular="font.ttf")
    except: pass

# --- UI 디자인 ---
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
            height: '45dp'
            canvas.before:
                Color:
                    rgba: 0.15, 0.3, 0.4, 1
                Rectangle:
                    pos: self.pos
                    size: self.size
            Label:
                text: "현재 파일: " + app.current_filename
                bold: True
                size_hint_x: 0.7
            Button:
                text: "자동저장: " + ("ON" if app.auto_save else "OFF")
                size_hint_x: 0.3
                background_color: (0.2, 0.6, 0.2, 1) if app.auto_save else (0.6, 0.2, 0.2, 1)
                on_release: app.toggle_auto_save()

        BoxLayout:
            size_hint_y: None
            height: '60dp'
            padding: '5dp'
            spacing: '5dp'
            Button:
                text: '외부설정'
                on_release: app.open_smb_settings()
            Button:
                text: '엑셀선택'
                on_release: app.select_source('file')
            Button:
                text: 'PDF폴더'
                on_release: app.select_source('dir')
            Button:
                text: '리셋'
                background_color: 0.8, 0.3, 0.3, 1
                on_release: app.show_reset_confirm()
            Button:
                text: '저장'
                background_color: 0.2, 0.7, 0.3, 1
                on_release: app.save_to_excel()

        BoxLayout:
            size_hint_y: None
            height: '35dp'
            canvas.before:
                Color:
                    rgba: 0.2, 0.2, 0.2, 1
                Rectangle:
                    pos: self.pos
                    size: self.size
            Button:
                text: 'No' + app.sort_indicator_no
                size_hint_x: 0.08
                on_release: app.sort_by('no')
            Button:
                text: '품목코드' + app.sort_indicator_code
                size_hint_x: 0.24
                on_release: app.sort_by('item_code')
            Button:
                text: '수량' + app.sort_indicator_qty
                size_hint_x: 0.08
                on_release: app.sort_by('quantity')
            Button:
                text: '완료' + app.sort_indicator_comp
                size_hint_x: 0.13
                on_release: app.sort_by('complete')
            Button:
                text: '부족' + app.sort_indicator_short
                size_hint_x: 0.13
                on_release: app.sort_by('shortage')
            Button:
                text: '재작업' + app.sort_indicator_rew
                size_hint_x: 0.14
                on_release: app.sort_by('rework')
            Label:
                text: '비고'
                size_hint_x: 0.2

        CheckSheetRV:
            id: rv
            viewclass: 'RowWidget'
            RecycleBoxLayout:
                default_size: None, dp(30)
                default_size_hint: 1, None
                size_hint_y: None
                height: self.minimum_height
                orientation: 'vertical'
                spacing: '1dp'

<RowWidget>:
    orientation: 'horizontal'
    padding: [1, 1]
    canvas.before:
        Color:
            rgba: 0.2, 0.2, 0.2, 1
        Rectangle:
            pos: self.pos
            size: self.size
    Label:
        text: root.no
        size_hint_x: 0.08
    Button:
        text: root.item_code
        size_hint_x: 0.24
        font_size: '13sp'
        background_normal: ''
        background_color: 0.2, 0.4, 0.6, 1
        on_release: root.open_pdf_external()
    Label:
        text: root.quantity
        size_hint_x: 0.08
    Button:
        text: 'V' if root.complete else ''
        size_hint_x: 0.13
        background_normal: ''
        background_color: (0, 0.8, 0, 0.6) if root.complete else (0.3, 0.3, 0.3, 1)
        on_release: root.on_status('complete')
    Button:
        text: 'V' if root.shortage else ''
        size_hint_x: 0.13
        background_normal: ''
        background_color: (0.8, 0.8, 0, 0.6) if root.shortage else (0.3, 0.3, 0.3, 1)
        on_release: root.on_status('shortage')
    Button:
        text: 'V' if root.rework else ''
        size_hint_x: 0.14
        background_normal: ''
        background_color: (0.8, 0, 0, 0.6) if root.rework else (0.3, 0.3, 0.3, 1)
        on_release: root.on_status('rework')
    TextInput:
        text: root.remarks
        size_hint_x: 0.2
        multiline: False
        font_size: '12sp'
        on_text: root.on_remarks_change(self.text)
"""

# --- Java 콜백용 전역 함수 ---
def update_status_from_java(item_code, status):
    app = App.get_running_app()
    if not app: return
    
    def update_data(dt):
        rv = app.root.get_screen('list').ids.rv
        found = False
        for d in rv.data:
            if d['item_code'] == item_code:
                if status == 'complete':
                    d['complete'] = not d['complete']
                    if d['complete']: d['shortage'] = d['rework'] = False
                elif status == 'shortage':
                    d['shortage'] = not d['shortage']
                    if d['shortage']: d['complete'] = d['rework'] = False
                elif status == 'rework':
                    d['rework'] = not d['rework']
                    if d['rework']: d['complete'] = d['shortage'] = False
                found = True; break
        
        if found:
            rv.refresh_from_data()
            if app.auto_save: app.save_to_excel(show_popup=False)
            
    Clock.schedule_once(update_data)

class ListScreen(Screen): pass
class CheckSheetRV(RecycleView): pass

class RowWidget(BoxLayout):
    no = StringProperty(''); item_code = StringProperty(''); quantity = StringProperty('')
    remarks = StringProperty(''); complete = BooleanProperty(False); shortage = BooleanProperty(False); rework = BooleanProperty(False)
    def on_status(self, st): App.get_running_app().update_item_status(self.item_code, self.no, st)
    def on_remarks_change(self, text): App.get_running_app().update_remarks_data(self.item_code, self.no, text)
    def open_pdf_external(self): App.get_running_app().open_pdf_viewer_flow(self.item_code)

class CheckSheetApp(App):
    SETTINGS_FILE = 'settings.json'
    LOCAL_BASE = "/sdcard/Download/CheckSheet" if platform == 'android' else os.path.join(os.getcwd(), "CheckSheet_Data")
    excel_path = StringProperty(''); pdf_folder_path = StringProperty('')
    current_filename = StringProperty('파일을 선택하세요'); auto_save = BooleanProperty(True)
    smb_config = DictProperty({'ip': '', 'user': '', 'pass': ''})
    sort_indicator_no = StringProperty(''); sort_indicator_code = StringProperty(''); sort_indicator_qty = StringProperty('')
    sort_indicator_comp = StringProperty(''); sort_indicator_short = StringProperty(''); sort_indicator_rew = StringProperty('')
    sort_states = {}

    def build(self):
        self.load_settings()
        Builder.load_string(KV_UI)
        sm = ScreenManager()
        sm.add_widget(ListScreen(name='list'))
        return sm

    def toggle_auto_save(self):
        self.auto_save = not self.auto_save
        self.save_settings()

    def on_start(self):
        Clock.schedule_once(self.delayed_init, 1)

    def delayed_init(self, dt):
        self.ask_permissions()
        if self.excel_path and os.path.exists(self.excel_path):
            self.load_excel_data(self.excel_path)

    def open_pdf_viewer_flow(self, item_code):
        rv = self.root.get_screen('list').ids.rv.data
        if not rv: return
        base_path = self.pdf_folder_path if self.pdf_folder_path else self.LOCAL_BASE
        file_list = []; target_index = 0
        for i, d in enumerate(rv):
            ic = d['item_code']
            p = os.path.join(base_path, f"{ic}.pdf")
            file_list.append(p)
            if ic == item_code: target_index = i
        try:
            from jnius import autoclass
            ArrayList = autoclass('java.util.ArrayList'); PdfActivity = autoclass('org.example.checksheetv163.PdfActivity')
            j_list = ArrayList()
            for f in file_list: j_list.add(f)
            PdfActivity.open(j_list, target_index)
        except Exception as e:
            self.show_popup("오류", f"내부 뷰어 실행 실패: {str(e)}\n빌드 설정을 확인하세요.")

    def ask_permissions(self):
        if platform != 'android': return
        try:
            from android.permissions import request_permissions, Permission
            from jnius import autoclass
            request_permissions([Permission.READ_EXTERNAL_STORAGE, Permission.WRITE_EXTERNAL_STORAGE, Permission.INTERNET])
            Env = autoclass('android.os.Environment')
            if hasattr(Env, 'isExternalStorageManager') and not Env.isExternalStorageManager():
                mActivity = autoclass('org.kivy.android.PythonActivity').mActivity
                Intent = autoclass('android.content.Intent'); Settings = autoclass('android.provider.Settings')
                uri = autoclass('android.net.Uri').fromParts("package", mActivity.getPackageName(), None)
                intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION); intent.setData(uri)
                mActivity.startActivity(intent)
        except: pass

    def load_excel_data(self, path):
        try:
            from openpyxl import load_workbook
            wb = load_workbook(path, data_only=True); ws = wb.active; rows = list(ws.rows)
            if not rows: return
            h = [str(c.value).strip().lower() if c.value else "" for c in rows[0]]
            def find_col(name_list, default_idx):
                for name in name_list:
                    if name in h: return h.index(name)
                return default_idx
            idx_no = find_col(['no', '번호'], 0); idx_code = find_col(['품목코드', 'code'], 1); idx_qty = find_col(['수량', 'qty'], 2)
            idx_comp = find_col(['완료', 'done'], 3); idx_short = find_col(['수량부족', 'short'], 4); idx_rew = find_col(['재작업', 'rework'], 5); idx_rem = find_col(['비고', 'remarks'], 6)
            rv_data = []
            for i, row in enumerate(rows[1:]):
                if len(row) <= idx_code or not row[idx_code].value: continue
                rv_data.append({
                    'no': str(row[idx_no].value or ''), 'item_code': str(row[idx_code].value or ''), 'quantity': str(row[idx_qty].value or ''),
                    'remarks': str(row[idx_rem].value or '') if len(row) > idx_rem else '',
                    'complete': str(row[idx_comp].value or '').upper() == 'V' if len(row) > idx_comp else False,
                    'shortage': str(row[idx_short].value or '').upper() == 'V' if len(row) > idx_short else False,
                    'rework': str(row[idx_rew].value or '').upper() == 'V' if len(row) > idx_rew else False,
                    'real_index': i
                })
            self.root.get_screen('list').ids.rv.data = rv_data
            self.current_filename = os.path.basename(path); self.excel_path = path
        except Exception as e: self.show_popup("로드 오류", str(e))

    def show_reset_confirm(self):
        content = BoxLayout(orientation='vertical', padding=20, spacing=20)
        content.add_widget(Label(text="모든 체크와 비고를 지우시겠습니까?"))
        btn_layout = BoxLayout(size_hint_y=None, height=dp(50), spacing=dp(10))
        pop = Popup(title="데이터 리셋", content=content, size_hint=(0.8, 0.4))
        btn_layout.add_widget(Button(text="아니오", on_release=pop.dismiss))
        btn_layout.add_widget(Button(text="예", on_release=lambda x: (self.reset_all_data(), pop.dismiss())))
        content.add_widget(btn_layout)
        pop.open()

    def reset_all_data(self):
        rv = self.root.get_screen('list').ids.rv
        if not rv.data: return
        for d in rv.data:
            d['complete'] = False; d['shortage'] = False; d['rework'] = False; d['remarks'] = ""
        rv.refresh_from_data()
        if self.auto_save: self.save_to_excel(show_popup=False)

    def sort_by(self, col):
        rv = self.root.get_screen('list').ids.rv
        if not rv.data: return
        new_s = 'desc' if self.sort_states.get(col) == 'asc' else 'asc'
        self.sort_states = {col: new_s}
        for k in ['no', 'code', 'qty', 'comp', 'short', 'rew']: setattr(self, f'sort_indicator_{k}', '')
        map_col = {'no':'no', 'item_code':'code', 'quantity':'qty', 'complete':'comp', 'shortage':'short', 'rework':'rew'}
        setattr(self, f'sort_indicator_{map_col[col]}', " ▲" if new_s == 'asc' else " ▼")
        def n_key(s):
            v = s.get(col, '')
            if isinstance(v, bool): return 1 if v else 0
            return [int(t) if t.isdigit() else t.lower() for t in re.split('([0-9]+)', str(v))]
        rv.data = sorted(rv.data, key=n_key, reverse=(new_s == 'desc')); rv.refresh_from_data()

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
        if self.auto_save: self.save_to_excel(show_popup=False)

    def update_remarks_data(self, ic, no, text):
        rv = self.root.get_screen('list').ids.rv
        for d in rv.data:
            if d['item_code'] == ic and d['no'] == no:
                d['remarks'] = text; break
        if self.auto_save and self.excel_path: self.save_to_excel(show_popup=False)

    def save_to_excel(self, show_popup=True):
        if not self.excel_path: return
        try:
            from openpyxl import load_workbook
            wb = load_workbook(self.excel_path); ws = wb.active; h = [str(c.value).strip() if c.value else "" for c in ws[1]]
            target = ['완료', '수량부족', '재작업', '비고']
            cols = {}
            for cn in target:
                if cn in h: cols[cn] = h.index(cn) + 1
                else:
                    ni = len(h) + 1; ws.cell(row=1, column=ni).value = cn; cols[cn] = ni; h.append(cn)
            for d in self.root.get_screen('list').ids.rv.data:
                r = d['real_index'] + 2
                ws.cell(row=r, column=cols['완료']).value = 'V' if d.get('complete') else ''
                ws.cell(row=r, column=cols['수량부족']).value = 'V' if d.get('shortage') else ''
                ws.cell(row=r, column=cols['재작업']).value = 'V' if d.get('rework') else ''
                ws.cell(row=r, column=cols['비고']).value = d.get('remarks', '')
            wb.save(self.excel_path)
            if show_popup: self.show_popup("알림", "저장 완료")
        except Exception as e:
            if show_popup: self.show_popup("저장 실패", str(e))

    def select_source(self, mode):
        content = BoxLayout(orientation='vertical', padding=20, spacing=20)
        pop = Popup(title="선택", content=content, size_hint=(0.8, 0.4))
        content.add_widget(Button(text="내 휴대폰", on_release=lambda x: (pop.dismiss(), self.open_local_browser(mode))))
        content.add_widget(Button(text="PC 공유폴더", on_release=lambda x: (pop.dismiss(), self.open_smb_shares_browser(mode))))
        pop.open()

    def open_local_browser(self, mode, path=None):
        if path is None:
            sp = ""
            if mode == 'file' and self.excel_path:
                d = os.path.dirname(self.excel_path)
                if os.path.exists(d): sp = d
            elif mode == 'dir' and self.pdf_folder_path:
                if os.path.exists(self.pdf_folder_path) and not self.pdf_folder_path.startswith("smb://"): sp = self.pdf_folder_path
            path = sp if sp else ("/storage/emulated/0" if platform=='android' else os.getcwd())
        content = BoxLayout(orientation='vertical'); lb = BoxLayout(orientation='vertical', size_hint_y=None); lb.bind(minimum_height=lb.setter('height')); scroll = ScrollView(); scroll.add_widget(lb); content.add_widget(scroll)
        pop = Popup(title=f"탐색: {path}", content=content, size_hint=(0.9, 0.9)); self.current_local_selection = None
        content.add_widget(Button(text="선택 완료", size_hint_y=None, height=dp(60), on_release=lambda x: self.confirm_local(mode, path, pop)))
        pd = os.path.dirname(path)
        if pd and pd != path:
            ub = Button(text=".. (상위)", size_hint_y=None, height=dp(50), background_color=(0.3, 0.3, 0.3, 1)); ub.bind(on_release=lambda x: (pop.dismiss(), self.open_local_browser(mode, pd))); lb.add_widget(ub)
        try:
            items = sorted(os.listdir(path)); ve = ['.xlsx', '.xls'] if mode == 'file' else ['.pdf']
            for item in items:
                fp = os.path.join(path, item); isd = os.path.isdir(fp)
                if not isd and os.path.splitext(item)[1].lower() not in ve: continue
                btn = Button(text=item + ("/" if isd else ""), size_hint_y=None, height=dp(50))
                if isd: btn.bind(on_release=lambda x, p=fp: (pop.dismiss(), self.open_local_browser(mode, p)))
                else: btn.bind(on_release=lambda x, p=fp: self.select_local_file(x, p, lb))
                lb.add_widget(btn)
        except: pass
        pop.open()

    def select_local_file(self, instance, p, lb):
        self.current_local_selection = p
        for c in lb.children: c.background_color = (1, 1, 1, 1)
        instance.background_color = (0.2, 0.4, 0.6, 1)

    def confirm_local(self, mode, path, pop):
        if mode == 'dir': self.pdf_folder_path = path; self.save_settings(); pop.dismiss()
        elif mode == 'file':
            if self.current_local_selection: self.excel_path = self.current_local_selection; self.load_excel_data(self.excel_path); self.save_settings(); pop.dismiss()
            else: self.show_popup("알림", "파일 선택 필요")

    def open_smb_shares_browser(self, mode):
        conn = self.get_smb_conn_only()
        if not conn: self.show_popup("알림", "SMB 실패"); return
        content = BoxLayout(orientation='vertical'); lb = BoxLayout(orientation='vertical', size_hint_y=None); lb.bind(minimum_height=lb.setter('height')); scroll = ScrollView(); scroll.add_widget(lb)
        pop = Popup(title="공유폴더", content=content, size_hint=(0.9, 0.9))
        try:
            for s in conn.listShares():
                if s.isSpecial or s.name.endswith('$'): continue
                b = Button(text=s.name, size_hint_y=None, height=80); b.bind(on_release=lambda x, n=s.name: self.open_smb_files_browser(conn, n, "/", mode, pop)); lb.add_widget(b)
        except: pass
        content.add_widget(scroll); pop.open()

    def open_smb_files_browser(self, conn, share, path, mode, parent):
        content = BoxLayout(orientation='vertical'); lb = BoxLayout(orientation='vertical', size_hint_y=None); lb.bind(minimum_height=lb.setter('height')); scroll = ScrollView(); scroll.add_widget(lb); content.add_widget(scroll)
        pop = Popup(title=f"SMB: {share}{path}", content=content, size_hint=(0.9, 0.9)); self.current_smb_selection = None
        def confirm(x):
            if mode == 'dir': self.pdf_folder_path = f"smb://{self.smb_config['ip']}/{share}{path}"; self.save_settings(); pop.dismiss(); parent.dismiss()
            elif mode == 'file' and self.current_smb_selection:
                fn, fp = self.current_smb_selection; local = os.path.join(self.LOCAL_BASE, fn)
                if not os.path.exists(self.LOCAL_BASE): os.makedirs(self.LOCAL_BASE)
                with open(local, 'wb') as lf: conn.retrieveFile(share, fp, lf)
                self.load_excel_data(local); self.save_settings(); pop.dismiss(); parent.dismiss()
        content.add_widget(Button(text="선택 완료", size_hint_y=None, height=dp(60), on_release=confirm))
        try:
            ve = ['.xlsx', '.xls'] if mode == 'file' else ['.pdf']
            for f in conn.listPath(share, path):
                if f.filename in ['.', '..']: continue
                if not f.isDirectory and os.path.splitext(f.filename)[1].lower() not in ve: continue
                btn = Button(text=f.filename + ("/" if f.isDirectory else ""), size_hint_y=None, height=dp(50))
                def click(ins, file=f):
                    np = os.path.join(path, file.filename).replace("\\", "/")
                    if file.isDirectory: pop.dismiss(); self.open_smb_files_browser(conn, share, np, mode, parent)
                    elif mode == 'file':
                        self.current_smb_selection = (file.filename, np)
                        for c in lb.children: c.background_color = (1, 1, 1, 1)
                        ins.background_color = (0.2, 0.4, 0.6, 1)
                btn.bind(on_release=click); lb.add_widget(btn)
        except: pass
        pop.open()

    def get_smb_conn_only(self):
        try:
            from smb.SMBConnection import SMBConnection
            c = self.smb_config; conn = SMBConnection(c['user'], c['pass'], "App", c['ip'], use_ntlm_v2=True, is_direct_tcp=True)
            if conn.connect(c['ip'], 445, timeout=3): return conn
        except: return None

    def open_smb_settings(self):
        content = BoxLayout(orientation='vertical', padding=10)
        ips = TextInput(text=self.smb_config['ip'], multiline=False); usr = TextInput(text=self.smb_config['user'], multiline=False); pas = TextInput(text=self.smb_config['pass'], password=True, multiline=False)
        content.add_widget(Label(text="IP")); content.add_widget(ips); content.add_widget(Label(text="ID")); content.add_widget(usr); content.add_widget(Label(text="PW")); content.add_widget(pas)
        def save(x): self.smb_config = {'ip':ips.text,'user':usr.text,'pass':pas.text}; self.save_settings(); pop.dismiss()
        content.add_widget(Button(text="저장", on_release=save)); pop = Popup(title="SMB 설정", content=content, size_hint=(0.8, 0.6)); pop.open()

    def load_settings(self):
        if os.path.exists(self.SETTINGS_FILE):
            try:
                with open(self.SETTINGS_FILE, 'r') as f:
                    d = json.load(f); self.excel_path = d.get('excel_path', ''); self.pdf_folder_path = d.get('pdf_folder_path', ''); self.smb_config = d.get('smb_config', {'ip':'','user':'','pass':''}); self.auto_save = d.get('auto_save', True)
            except: pass

    def save_settings(self):
        with open(self.SETTINGS_FILE, 'w') as f: json.dump({'excel_path': self.excel_path, 'pdf_folder_path': self.pdf_folder_path, 'smb_config': self.smb_config, 'auto_save': self.auto_save}, f)

    def show_popup(self, title, msg): Popup(title=title, content=Label(text=str(msg)), size_hint=(0.8, 0.4)).open()

if __name__ == '__main__':
    CheckSheetApp().run()
