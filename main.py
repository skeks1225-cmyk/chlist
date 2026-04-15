import os
import json
import traceback
import subprocess
from openpyxl import load_workbook

from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.recycleview import RecycleView
from kivy.properties import StringProperty, BooleanProperty, NumericProperty
from kivy.uix.popup import Popup
from kivy.uix.filechooser import FileChooserListView
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.core.text import LabelBase
from kivy.utils import platform
from kivy.clock import Clock

# 한글 폰트 설정
try:
    FONT_NAME = "font.ttf"
    if os.path.exists(FONT_NAME):
        LabelBase.register(name="Roboto", fn_regular=FONT_NAME)
except Exception as e:
    print(f"Font Error: {e}")

SETTINGS_FILE = 'settings.json'

class RowWidget(BoxLayout):
    no = StringProperty('')
    item_code = StringProperty('')
    quantity = StringProperty('')
    complete = BooleanProperty(False)
    shortage = BooleanProperty(False)
    rework = BooleanProperty(False)
    index = NumericProperty(0)

    def on_checkbox_active(self, checkbox_type):
        try:
            app = App.get_running_app()
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
        except: pass

    def open_pdf(self):
        try:
            app = App.get_running_app()
            if not app.pdf_folder_path: 
                app.show_error_popup("PDF 폴더를 먼저 설정해 주세요.")
                return
            pdf_path = os.path.join(app.pdf_folder_path, f"{self.item_code}.pdf")
            if not os.path.exists(pdf_path):
                app.show_error_popup(f"PDF 파일 없음:\n{self.item_code}.pdf")
                return

            if platform == 'android':
                from jnius import autoclass, cast
                PythonActivity = autoclass('org.kivy.android.PythonActivity')
                Intent = autoclass('android.content.Intent')
                Uri = autoclass('android.net.Uri')
                File = autoclass('java.io.File')
                try:
                    StrictMode = autoclass('android.os.StrictMode')
                    StrictMode.disableDeathOnFileUriExposure()
                except: pass
                file = File(pdf_path)
                uri = Uri.fromFile(file)
                intent = Intent(Intent.ACTION_VIEW)
                intent.setDataAndType(uri, "application/pdf")
                intent.setFlags(Intent.FLAG_ACTIVITY_NO_HISTORY | Intent.FLAG_GRANT_READ_URI_PERMISSION)
                currentActivity = cast('android.app.Activity', PythonActivity.mActivity)
                currentActivity.startActivity(intent)
            else:
                if os.name == 'nt': os.startfile(pdf_path)
                else: subprocess.run(['xdg-open', pdf_path])
        except Exception as e:
            App.get_running_app().show_error_popup(f"PDF 열기 오류: {e}")

class CheckSheetRV(RecycleView):
    pass

class RootWidget(BoxLayout):
    pass

class CheckSheetApp(App):
    excel_path = StringProperty('')
    pdf_folder_path = StringProperty('')

    def build(self):
        try:
            self.load_settings()
            return RootWidget()
        except Exception as e:
            error_layout = BoxLayout(orientation='vertical')
            error_layout.add_widget(Label(text=f"ERROR: {e}"))
            return error_layout

    def on_start(self):
        if platform == 'android':
            Clock.schedule_once(self.ask_permissions, 1)
        if self.excel_path and os.path.exists(self.excel_path):
            self.load_excel_data(self.excel_path)

    def ask_permissions(self, dt):
        if platform == 'android':
            try:
                from jnius import autoclass
                from android.permissions import request_permissions, Permission
                
                # 기본 저장소 권한 요청
                request_permissions([Permission.READ_EXTERNAL_STORAGE, Permission.WRITE_EXTERNAL_STORAGE])
                
                # Android 11+ 전체 파일 관리 권한 체크 및 설정창 유도
                Environment = autoclass('android.os.Environment')
                if not Environment.isExternalStorageManager():
                    Context = autoclass('org.kivy.android.PythonActivity').mActivity
                    Intent = autoclass('android.content.Intent')
                    Settings = autoclass('android.provider.Settings')
                    Uri = autoclass('android.net.Uri')
                    
                    intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                    uri = Uri.fromParts("package", Context.getPackageName(), None)
                    intent.setData(uri)
                    Context.startActivity(intent)
                    self.show_error_popup("원활한 사용을 위해\n'모든 파일 관리 권한'을 허용해 주세요.")
            except Exception as e:
                print(f"Permission Request Error: {e}")

    def show_error_popup(self, error_msg):
        Popup(title="알림", content=Label(text=error_msg, halign='center'), size_hint=(0.8, 0.4)).open()

    def load_settings(self):
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, 'r', encoding='utf-8') as f:
                    settings = json.load(f)
                    self.excel_path = settings.get('excel_path', '')
                    self.pdf_folder_path = settings.get('pdf_folder_path', '')
            except: pass

    def save_settings(self):
        with open(SETTINGS_FILE, 'w', encoding='utf-8') as f:
            json.dump({'excel_path': self.excel_path, 'pdf_folder_path': self.pdf_folder_path}, f, ensure_ascii=False)

    def open_file_chooser(self, mode='file'):
        try:
            # 안드로이드에서는 /sdcard 또는 /storage/emulated/0 부터 시작
            start_path = "/sdcard" if platform == 'android' else os.getcwd()
            file_chooser = FileChooserListView(path=start_path)
            if mode == 'dir': file_chooser.dirselect = True
            
            content = BoxLayout(orientation='vertical')
            popup = Popup(title="파일/폴더 선택 (공유폴더 접근 불가)", content=content, size_hint=(0.9, 0.9))
            
            def on_select(instance):
                if file_chooser.selection:
                    path = file_chooser.selection[0]
                    if mode == 'file':
                        self.excel_path = path
                        self.load_excel_data(path)
                    else: self.pdf_folder_path = path
                    self.save_settings()
                popup.dismiss()

            btn_layout = BoxLayout(size_hint_y=None, height=50)
            btn_layout.add_widget(Button(text="선택", on_release=on_select))
            btn_layout.add_widget(Button(text="취on_release", on_release=popup.dismiss))
            
            content.add_widget(file_chooser)
            content.add_widget(btn_layout)
            popup.open()
        except Exception as e:
            self.show_error_popup(f"탐색기 에러: {e}")

    def load_excel_data(self, path):
        try:
            wb = load_workbook(path, data_only=True)
            ws = wb.active
            rows = list(ws.rows)
            if not rows: return
            headers = [str(cell.value).strip().lower() for cell in rows[0]]
            try:
                idx_no, idx_code, idx_qty = headers.index('no'), headers.index('품목코드'), headers.index('수량')
            except ValueError:
                self.show_error_popup("엑셀 헤더 오류 (no, 품목코드, 수량 필요)")
                return
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
        except Exception as e:
            self.show_error_popup(f"로드 실패: {e}")

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
            self.show_error_popup("저장 완료!")
        except Exception as e:
            self.show_error_popup(f"저장 실패: {e}")

if __name__ == '__main__':
    CheckSheetApp().run()
