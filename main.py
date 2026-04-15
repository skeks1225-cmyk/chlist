import os
import json
import traceback
import subprocess
import socket
from openpyxl import load_workbook

from kivy.app import App
from kivy.core.window import Window
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.recycleview import RecycleView
from kivy.properties import StringProperty, BooleanProperty, NumericProperty, DictProperty
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

# 안드로이드 키보드 가림 방지
if platform == 'android':
    Window.softinput_mode = 'below_target'

# SMB 라이브러리
SMB_AVAILABLE = False
IMPORT_ERROR = ""
try:
    from smb.SMBConnection import SMBConnection
    SMB_AVAILABLE = True
except Exception as e:
    IMPORT_ERROR = str(e)

# 한글 폰트
try:
    FONT_NAME = "font.ttf"
    if os.path.exists(FONT_NAME):
        LabelBase.register(name="Roboto", fn_regular=FONT_NAME)
except: pass

SETTINGS_FILE = 'settings.json'
LOCAL_BASE = "/sdcard/Download/CheckSheet" if platform == 'android' else os.path.join(os.getcwd(), "CheckSheet_Data")
if not os.path.exists(LOCAL_BASE):
    os.makedirs(LOCAL_BASE)

class RowWidget(BoxLayout):
    no = StringProperty('')
    item_code = StringProperty('')
    quantity = StringProperty('')
    complete = BooleanProperty(False)
    shortage = BooleanProperty(False)
    rework = BooleanProperty(False)
    index = NumericProperty(0)

    def on_checkbox_active(self, checkbox_type):
        app = App.get_running_app()
        if not app.root or not app.root.ids.rv.data: return
        rv_data = app.root.ids.rv.data[self.index]
        if checkbox_type == 'complete':
            rv_data['complete'] = not self.complete
            if rv_data['complete']: rv_data['shortage'], rv_data['rework'] = False, False
        elif checkbox_type == 'shortage':
            rv_data['shortage'] = not self.shortage
            if rv_data['shortage']: rv_data['complete'], rv_data['rework'] = False, False
        elif checkbox_type == 'rework':
            rv_data['rework'] = not self.rework
            if rv_data['rework']: rv_data['complete'], rv_data['shortage'] = False, False
        app.root.ids.rv.refresh_from_data()

    def open_pdf(self):
        App.get_running_app().handle_pdf_click(self.item_code)

class CheckSheetRV(RecycleView):
    pass

class RootWidget(BoxLayout):
    pass

class CheckSheetApp(App):
    excel_path = StringProperty('')
    pdf_folder_path = StringProperty('') # 예: "ShareName/Path/To/Folder"
    pdf_source = StringProperty('local')
    excel_source = StringProperty('local')
    smb_config = DictProperty({'ip': '', 'user': '', 'pass': ''})

    def build(self):
        self.load_settings()
        return RootWidget()

    def on_start(self):
        if platform == 'android':
            Clock.schedule_once(self.ask_permissions, 1)
        if self.excel_path and os.path.exists(self.excel_path):
            self.load_excel_data(self.excel_path)

    def ask_permissions(self, dt):
        if platform == 'android':
            try:
                from android.permissions import request_permissions, Permission
                from jnius import autoclass
                request_permissions([
                    Permission.READ_EXTERNAL_STORAGE, Permission.WRITE_EXTERNAL_STORAGE, 
                    Permission.INTERNET, Permission.ACCESS_NETWORK_STATE
                ])
                Env = autoclass('android.os.Environment')
                if not Env.isExternalStorageManager():
                    Context = autoclass('org.kivy.android.PythonActivity').mActivity
                    Intent = autoclass('android.content.Intent')
                    Settings = autoclass('android.provider.Settings')
                    Uri = autoclass('android.net.Uri')
                    intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                    uri = Uri.fromParts("package", Context.getPackageName(), None)
                    intent.setData(uri)
                    Context.startActivity(intent)
            except: pass

    def load_settings(self):
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, 'r', encoding='utf-8') as f:
                    d = json.load(f)
                    self.excel_path = d.get('excel_path', '')
                    self.pdf_folder_path = d.get('pdf_folder_path', '')
                    self.pdf_source = d.get('pdf_source', 'local')
                    self.excel_source = d.get('excel_source', 'local')
                    self.smb_config = d.get('smb_config', {'ip': '', 'user': '', 'pass': ''})
            except: pass

    def save_settings(self):
        with open(SETTINGS_FILE, 'w', encoding='utf-8') as f:
            json.dump({
                'excel_path': self.excel_path, 'pdf_folder_path': self.pdf_folder_path,
                'pdf_source': self.pdf_source, 'excel_source': self.excel_source,
                'smb_config': self.smb_config
            }, f, ensure_ascii=False)

    def open_smb_settings(self):
        scroll = ScrollView(size_hint=(1, 1))
        content = BoxLayout(orientation='vertical', padding=dp(20), spacing=dp(20), size_hint_y=None)
        content.bind(minimum_height=content.setter('height'))
        
        inputs = {}
        fields = [
            ('ip', '1. 접속 IP 주소 (예: 100.x.x.x)'), 
            ('user', '2. 사용자 ID (윈도우 계정)'), 
            ('pass', '3. 비밀번호 (윈도우 암호)')
        ]
        
        for key, hint in fields:
            content.add_widget(Label(text=hint, size_hint_y=None, height=dp(40), halign='left', text_size=(Window.width*0.85, None), font_size='16sp', bold=True))
            ti = TextInput(text=self.smb_config.get(key, ''), multiline=False, size_hint_y=None, height=dp(100), font_size='22sp', padding=[dp(15), dp(25)])
            if key == 'pass': ti.password = True
            content.add_widget(ti)
            inputs[key] = ti
        
        popup = Popup(title="SMB 접속 설정 (자동 검색 모드)", content=scroll, size_hint=(0.95, 0.9))
        scroll.add_widget(content)
        
        def save_and_close(instance):
            self.smb_config = {k: v.text.strip() for k, v in inputs.items()}
            self.save_settings()
            popup.dismiss()
            self.show_error_popup("설정 저장됨.\n파일 선택을 눌러 확인하세요.")

        content.add_widget(Button(text="접속 정보 저장", size_hint_y=None, height=dp(90), on_release=save_and_close, background_color=(0, 0.6, 0.8, 1), font_size='20sp'))
        content.add_widget(BoxLayout(size_hint_y=None, height=dp(150)))
        popup.open()

    def get_smb_conn(self):
        if not SMB_AVAILABLE: return None, f"SMB 라이브러리 오류:\n{IMPORT_ERROR}"
        ip = self.smb_config['ip']
        if not ip: return None, "IP 주소를 먼저 입력하세요"
        
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(3); result = s.connect_ex((ip, 445)); s.close()
            if result != 0: return None, "PC 연결 불가 (포트 445 차단됨)"

            conn = SMBConnection(
                self.smb_config['user'], self.smb_config['pass'], 
                "CheckSheetApp", ip, use_ntlm_v2=True, is_direct_tcp=True
            )
            if conn.connect(ip, 445, timeout=5): return conn, None
            return None, "ID/PW 오류 또는 접속 거부"
        except Exception as e: return None, f"에러: {e}"

    def select_source(self, mode):
        content = BoxLayout(orientation='vertical', padding=dp(20), spacing=dp(20))
        popup = Popup(title="파일 출처 선택", content=content, size_hint=(0.85, 0.5))
        def on_choice(choice):
            popup.dismiss()
            if choice == 'local':
                if mode == 'excel': self.excel_source = 'local'; self.open_local_browser('file')
                else: self.pdf_source = 'local'; self.open_local_browser('dir')
            else:
                if mode == 'excel': self.excel_source = 'smb'; self.open_smb_shares_browser('file')
                else: self.pdf_source = 'smb'; self.open_smb_shares_browser('dir')
            self.save_settings()
        content.add_widget(Button(text="휴대폰 저장소", on_release=lambda x: on_choice('local'), font_size='18sp'))
        content.add_widget(Button(text="PC 공유 폴더", on_release=lambda x: on_choice('smb'), font_size='18sp'))
        popup.open()

    def open_smb_shares_browser(self, mode):
        conn, err = self.get_smb_conn()
        if not conn: self.show_error_popup(f"접속 실패:\n{err}"); return
        
        content = BoxLayout(orientation='vertical')
        scroll = ScrollView(); list_box = BoxLayout(orientation='vertical', size_hint_y=None, spacing=dp(5))
        list_box.bind(minimum_height=list_box.setter('height')); scroll.add_widget(list_box)
        popup = Popup(title="공유 폴더를 선택하세요", content=content, size_hint=(0.95, 0.95))
        
        try:
            shares = conn.listShares()
            for s in shares:
                if s.isSpecial or s.name.endswith('$'): continue
                btn = Button(text=f"📁 {s.name}", size_hint_y=None, height=dp(90), font_size='20sp')
                btn.bind(on_release=lambda b, s=s: self.open_smb_files_browser(conn, s.name, "/", mode, popup))
                list_box.add_widget(btn)
        except Exception as e:
            list_box.add_widget(Label(text=f"공유 목록 읽기 오류:\n{e}"))
        
        content.add_widget(scroll)
        content.add_widget(Button(text="취소", size_hint_y=None, height=dp(80), on_release=lambda x: (conn.close(), popup.dismiss())))
        popup.open()

    def open_smb_files_browser(self, conn, share_name, path, mode, parent_popup):
        content = BoxLayout(orientation='vertical')
        scroll = ScrollView(); list_box = BoxLayout(orientation='vertical', size_hint_y=None, spacing=dp(5))
        list_box.bind(minimum_height=list_box.setter('height')); scroll.add_widget(list_box)
        popup = Popup(title=f"SMB: {share_name}{path}", content=content, size_hint=(0.95, 0.95))
        
        def refresh(current_path):
            list_box.clear_widgets()
            if current_path != "/":
                btn = Button(text=".. (상위 폴더)", size_hint_y=None, height=dp(80), background_color=(0.4, 0.4, 0.4, 1))
                btn.bind(on_release=lambda x: refresh(os.path.dirname(current_path.rstrip("/")) or "/"))
                list_box.add_widget(btn)
            
            try:
                files = conn.listPath(share_name, current_path)
                for f in files:
                    if f.filename in ['.', '..']: continue
                    display_text = f"{'📁' if f.isDirectory else '📄'} {f.filename}"
                    btn = Button(text=display_text, size_hint_y=None, height=dp(90), halign='left', padding=[dp(20), 0], font_size='18sp')
                    btn.bind(on_release=lambda b, f=f: on_click(current_path, f))
                    list_box.add_widget(btn)
            except Exception as e: list_box.add_widget(Label(text=f"오류: {e}"))

        def on_click(curr_p, f):
            new_path = os.path.join(curr_p, f.filename).replace("\\", "/")
            if f.isDirectory:
                if mode == 'dir':
                    self.pdf_folder_path = f"{share_name}{new_path}"
                    self.save_settings(); popup.dismiss(); parent_popup.dismiss(); conn.close()
                else: refresh(new_path)
            else:
                if mode == 'file':
                    self.download_from_smb(conn, share_name, new_path)
                    popup.dismiss(); parent_popup.dismiss(); conn.close()

        refresh(path)
        content.add_widget(scroll)
        content.add_widget(Button(text="창 닫기", size_hint_y=None, height=dp(80), on_release=lambda x: popup.dismiss()))
        popup.open()

    def download_from_smb(self, conn, share_name, remote_path):
        local_path = os.path.join(LOCAL_BASE, os.path.basename(remote_path))
        try:
            with open(local_path, 'wb') as f:
                conn.retrieveFile(share_name, remote_path, f)
            self.excel_path = local_path; self.load_excel_data(local_path); self.save_settings()
        except Exception as e: self.show_error_popup(f"다운로드 실패: {e}")

    def handle_pdf_click(self, item_code):
        if not self.pdf_folder_path: self.show_error_popup("PDF 폴더를 먼저 설정하세요."); return
        if self.pdf_source == 'local':
            path = os.path.join(self.pdf_folder_path, f"{item_code}.pdf")
            if os.path.exists(path): self.open_local_pdf(path)
            else: self.show_error_popup("파일이 없습니다.")
        else:
            self.download_and_open_pdf_smb(item_code)

    def download_and_open_pdf_smb(self, item_code):
        # pdf_folder_path 예: "MyShare/Drawings"
        parts = self.pdf_folder_path.split("/", 1)
        share_name = parts[0]
        sub_path = parts[1] if len(parts) > 1 else ""
        remote_path = os.path.join("/", sub_path, f"{item_code}.pdf").replace("\\", "/")
        local_path = os.path.join(LOCAL_BASE, f"{item_code}.pdf")
        
        if os.path.exists(local_path): self.open_local_pdf(local_path); return
        conn, _ = self.get_smb_conn()
        if not conn: return
        try:
            with open(local_path, 'wb') as f:
                conn.retrieveFile(share_name, remote_path, f)
            self.open_local_pdf(local_path)
        except: self.show_error_popup("SMB에서 PDF를 찾을 수 없습니다.")
        finally: conn.close()

    def open_local_pdf(self, path):
        if platform == 'android':
            try:
                from jnius import autoclass, cast
                Activity = autoclass('org.kivy.android.PythonActivity').mActivity
                Intent = autoclass('android.content.Intent'); Uri = autoclass('android.net.Uri'); File = autoclass('java.io.File')
                autoclass('android.os.StrictMode').disableDeathOnFileUriExposure()
                intent = Intent(Intent.ACTION_VIEW)
                intent.setDataAndType(Uri.fromFile(File(path)), "application/pdf")
                intent.setFlags(Intent.FLAG_ACTIVITY_NO_HISTORY | Intent.FLAG_GRANT_READ_URI_PERMISSION)
                Activity.startActivity(intent)
            except Exception as e: self.show_error_popup(f"PDF 실행 실패: {e}")
        else:
            if os.name == 'nt': os.startfile(path)
            else: subprocess.run(['xdg-open', path])

    def open_local_browser(self, mode):
        start_path = "/sdcard" if platform == 'android' else os.getcwd()
        content = BoxLayout(orientation='vertical')
        fc = FileChooserListView(path=start_path)
        if mode == 'dir': fc.dirselect = True
        popup = Popup(title="휴대폰 파일 선택", content=content, size_hint=(0.95, 0.95))
        def on_select(instance):
            if fc.selection:
                path = fc.selection[0]
                if mode == 'file': self.excel_path = path; self.load_excel_data(path)
                else: self.pdf_folder_path = path
                self.save_settings()
            popup.dismiss()
        btn_layout = BoxLayout(size_hint_y=None, height=dp(70), spacing=dp(10))
        btn_layout.add_widget(Button(text="취소", on_release=popup.dismiss))
        btn_layout.add_widget(Button(text="선택 완료", on_release=on_select, background_color=(0, 0.7, 0, 1)))
        content.add_widget(fc); content.add_widget(btn_layout)
        popup.open()

    def load_excel_data(self, path):
        try:
            wb = load_workbook(path, data_only=True)
            ws = wb.active; rows = list(ws.rows)
            headers = [str(cell.value).strip().lower() for cell in rows[0]]
            idx_no, idx_code, idx_qty = headers.index('no'), headers.index('품목코드'), headers.index('수량')
            rv_data = []
            for i, row in enumerate(rows[1:]):
                rv_data.append({
                    'no': str(row[idx_no].value or ''), 'item_code': str(row[idx_code].value or ''), 'quantity': str(row[idx_qty].value or ''),
                    'complete': str(ws.cell(row=i+2, column=headers.index('완료')+1).value or '').upper() == 'V' if '완료' in headers else False,
                    'shortage': str(ws.cell(row=i+2, column=headers.index('수량부족')+1).value or '').upper() == 'V' if '수량부족' in headers else False,
                    'rework': str(ws.cell(row=i+2, column=headers.index('재작업')+1).value or '').upper() == 'V' if '재작업' in headers else False,
                    'index': i
                })
            self.root.ids.rv.data = rv_data
        except: self.show_error_popup("엑셀 양식이 올바르지 않습니다.")

    def save_to_excel(self):
        if not self.excel_path: return
        try:
            wb = load_workbook(self.excel_path)
            ws = wb.active; headers = [str(cell.value).strip().lower() for cell in ws[1]]
            cols = {'완료': -1, '수량부족': -1, '재작업': -1}
            for k in cols:
                if k in headers: cols[k] = headers.index(k) + 1
            for data in self.root.ids.rv.data:
                row_idx = data['index'] + 2
                if cols['완료'] > 0: ws.cell(row=row_idx, column=cols['완료']).value = 'V' if data['complete'] else ''
                if cols['수량부족'] > 0: ws.cell(row=row_idx, column=cols['수량부족']).value = 'V' if data['shortage'] else ''
                if cols['재작업'] > 0: ws.cell(row=row_idx, column=cols['재작업']).value = 'V' if data['rework'] else ''
            wb.save(self.excel_path)
            self.show_error_popup(f"폰에 저장 완료!\n{os.path.basename(self.excel_path)}")
        except Exception as e: self.show_error_popup(f"저장 실패: {e}")

    def show_error_popup(self, msg):
        Popup(title="알림", content=Label(text=msg, halign='center'), size_hint=(0.9, 0.5)).open()

if __name__ == '__main__':
    CheckSheetApp().run()
