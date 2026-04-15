import os
import json
import traceback
import subprocess
from tempfile import NamedTemporaryFile
from openpyxl import load_workbook

from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.recycleview import RecycleView
from kivy.properties import StringProperty, BooleanProperty, NumericProperty, DictProperty
from kivy.uix.popup import Popup
from kivy.uix.filechooser import FileChooserListView
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.textinput import TextInput
from kivy.core.text import LabelBase
from kivy.utils import platform
from kivy.clock import Clock

# SMB 라이브러리 (pysmb)
try:
    from nmb.NetBIOS import NetBIOS
    from smb.SMBConnection import SMBConnection
    SMB_AVAILABLE = True
except ImportError:
    SMB_AVAILABLE = False

# 한글 폰트
try:
    FONT_NAME = "font.ttf"
    if os.path.exists(FONT_NAME):
        LabelBase.register(name="Roboto", fn_regular=FONT_NAME)
except: pass

SETTINGS_FILE = 'settings.json'
LOCAL_STORAGE = "/sdcard/Download/CheckSheet" if platform == 'android' else os.path.join(os.getcwd(), "CheckSheet_Local")

if not os.path.exists(LOCAL_STORAGE):
    os.makedirs(LOCAL_STORAGE)

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
        if not app.root.ids.rv.data: return
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
        app = App.get_running_app()
        app.download_and_open_pdf(self.item_code)

class CheckSheetRV(RecycleView):
    pass

class RootWidget(BoxLayout):
    pass

class CheckSheetApp(App):
    excel_path = StringProperty('')
    pdf_folder_path = StringProperty('') # SMB 내의 경로
    smb_config = DictProperty({'ip': '', 'user': '', 'pass': '', 'share': ''})

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
                request_permissions([Permission.READ_EXTERNAL_STORAGE, Permission.WRITE_EXTERNAL_STORAGE, Permission.INTERNET])
                
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
                    data = json.load(f)
                    self.excel_path = data.get('excel_path', '')
                    self.pdf_folder_path = data.get('pdf_folder_path', '')
                    self.smb_config = data.get('smb_config', {'ip': '', 'user': '', 'pass': '', 'share': ''})
            except: pass

    def save_settings(self):
        with open(SETTINGS_FILE, 'w', encoding='utf-8') as f:
            json.dump({
                'excel_path': self.excel_path, 
                'pdf_folder_path': self.pdf_folder_path,
                'smb_config': self.smb_config
            }, f, ensure_ascii=False)

    def open_smb_settings(self):
        content = BoxLayout(orientation='vertical', padding=10, spacing=5)
        inputs = {}
        for key in ['ip', 'user', 'pass', 'share']:
            row = BoxLayout(size_hint_y=None, height=40)
            row.add_widget(Label(text=key.upper(), size_hint_x=0.3))
            ti = TextInput(text=self.smb_config.get(key, ''), multiline=False)
            if key == 'pass': ti.password = True
            row.add_widget(ti)
            inputs[key] = ti
            content.add_widget(row)
        
        popup = Popup(title="SMB 설정 (IP, ID, PW, 폴더명)", content=content, size_hint=(0.9, 0.6))
        def save(instance):
            self.smb_config = {k: v.text for k, v in inputs.items()}
            self.save_settings()
            popup.dismiss()
        content.add_widget(Button(text="저장", size_hint_y=None, height=50, on_release=save))
        popup.open()

    def get_smb_conn(self):
        if not SMB_AVAILABLE: return None
        try:
            conn = SMBConnection(self.smb_config['user'], self.smb_config['pass'], "KivyClient", "RemoteServer", use_ntlm_v2=True)
            if conn.connect(self.smb_config['ip'], 445, timeout=5):
                return conn
        except: pass
        return None

    def open_smb_browser(self, mode='file'):
        conn = self.get_smb_conn()
        if not conn:
            self.show_error_popup("SMB 접속 실패. 설정을 확인하세요.")
            return

        content = BoxLayout(orientation='vertical')
        list_box = BoxLayout(orientation='vertical')
        popup = Popup(title="SMB 파일 선택", content=content, size_hint=(0.9, 0.9))
        
        current_path = "/"
        
        def refresh_list(path):
            list_box.clear_widgets()
            try:
                files = conn.listPath(self.smb_config['share'], path)
                for f in files:
                    if f.filename in ['.', '..']: continue
                    btn = Button(text=f"{'[DIR] ' if f.isDirectory else ''}{f.filename}", size_hint_y=None, height=50)
                    btn.bind(on_release=lambda b, f=f: on_item_click(path, f))
                    list_box.add_widget(btn)
            except: 
                list_box.add_widget(Label(text="목록을 불러올 수 없습니다."))

        def on_item_click(path, f):
            new_path = os.path.join(path, f.filename).replace("\\", "/")
            if f.isDirectory:
                if mode == 'dir':
                    self.pdf_folder_path = new_path
                    self.save_settings()
                    popup.dismiss()
                else: refresh_list(new_path)
            else:
                if mode == 'file':
                    self.download_excel_from_smb(new_path)
                    popup.dismiss()

        refresh_list(current_path)
        from kivy.uix.scrollview import ScrollView
        sv = ScrollView()
        sv.add_widget(list_box)
        content.add_widget(sv)
        content.add_widget(Button(text="닫기", size_hint_y=None, height=50, on_release=popup.dismiss))
        popup.open()

    def download_excel_from_smb(self, remote_path):
        conn = self.get_smb_conn()
        if not conn: return
        local_path = os.path.join(LOCAL_STORAGE, os.path.basename(remote_path))
        try:
            with open(local_path, 'wb') as f:
                conn.retrieveFile(self.smb_config['share'], remote_path, f)
            self.excel_path = local_path
            self.load_excel_data(local_path)
            self.save_settings()
        except Exception as e:
            self.show_error_popup(f"다운로드 실패: {e}")
        finally: conn.close()

    def download_and_open_pdf(self, item_code):
        if not self.pdf_folder_path:
            self.show_error_popup("PDF 공유 폴더를 먼저 설정하세요.")
            return
        
        remote_path = os.path.join(self.pdf_folder_path, f"{item_code}.pdf").replace("\\", "/")
        local_path = os.path.join(LOCAL_STORAGE, f"{item_code}.pdf")
        
        # 이미 있으면 바로 열기
        if os.path.exists(local_path):
            self.open_local_pdf(local_path)
            return

        conn = self.get_smb_conn()
        if not conn: return
        try:
            with open(local_path, 'wb') as f:
                conn.retrieveFile(self.smb_config['share'], remote_path, f)
            self.open_local_pdf(local_path)
        except:
            self.show_error_popup(f"PDF를 찾을 수 없거나 다운로드 실패:\n{item_code}.pdf")
        finally: conn.close()

    def open_local_pdf(self, path):
        if platform == 'android':
            try:
                from jnius import autoclass, cast
                PythonActivity = autoclass('org.kivy.android.PythonActivity')
                Intent = autoclass('android.content.Intent')
                Uri = autoclass('android.net.Uri')
                File = autoclass('java.io.File')
                StrictMode = autoclass('android.os.StrictMode')
                StrictMode.disableDeathOnFileUriExposure()
                
                file = File(path)
                uri = Uri.fromFile(file)
                intent = Intent(Intent.ACTION_VIEW)
                intent.setDataAndType(uri, "application/pdf")
                intent.setFlags(Intent.FLAG_ACTIVITY_NO_HISTORY | Intent.FLAG_GRANT_READ_URI_PERMISSION)
                currentActivity = cast('android.app.Activity', PythonActivity.mActivity)
                currentActivity.startActivity(intent)
            except Exception as e:
                self.show_error_popup(f"PDF 앱 실행 실패: {e}")
        else:
            if os.name == 'nt': os.startfile(path)
            else: subprocess.run(['xdg-open', path])

    def load_excel_data(self, path):
        try:
            wb = load_workbook(path, data_only=True)
            ws = wb.active
            rows = list(ws.rows)
            headers = [str(cell.value).strip().lower() for cell in rows[0]]
            idx_no, idx_code, idx_qty = headers.index('no'), headers.index('품목코드'), headers.index('수량')
            rv_data = []
            for i, row in enumerate(rows[1:]):
                rv_data.append({
                    'no': str(row[idx_no].value or ''),
                    'item_code': str(row[idx_code].value or ''),
                    'quantity': str(row[idx_qty].value or ''),
                    'complete': str(ws.cell(row=i+2, column=headers.index('완료')+1).value or '').upper() == 'V' if '완료' in headers else False,
                    'shortage': str(ws.cell(row=i+2, column=headers.index('수량부족')+1).value or '').upper() == 'V' if '수량부족' in headers else False,
                    'rework': str(ws.cell(row=i+2, column=headers.index('재작업')+1).value or '').upper() == 'V' if '재작업' in headers else False,
                    'index': i
                })
            self.root.ids.rv.data = rv_data
        except: self.show_error_popup("엑셀 파일 로드 실패")

    def save_to_excel(self):
        if not self.excel_path: return
        try:
            wb = load_workbook(self.excel_path)
            ws = wb.active
            headers = [str(cell.value).strip().lower() for cell in ws[1]]
            cols = {'완료': -1, '수량부족': -1, '재작업': -1}
            for k in cols:
                if k in headers: cols[k] = headers.index(k) + 1
            for data in self.root.ids.rv.data:
                row_idx = data['index'] + 2
                if cols['완료'] > 0: ws.cell(row=row_idx, column=cols['완료']).value = 'V' if data['complete'] else ''
                if cols['수량부족'] > 0: ws.cell(row=row_idx, column=cols['수량부족']).value = 'V' if data['shortage'] else ''
                if cols['재작업'] > 0: ws.cell(row=row_idx, column=cols['재작업']).value = 'V' if data['rework'] else ''
            wb.save(self.excel_path)
            self.show_error_popup(f"저장 성공!\n{os.path.basename(self.excel_path)}")
        except Exception as e:
            self.show_error_popup(f"저장 실패: {e}")

    def show_error_popup(self, msg):
        Popup(title="알림", content=Label(text=msg, halign='center'), size_hint=(0.8, 0.4)).open()

if __name__ == '__main__':
    CheckSheetApp().run()
