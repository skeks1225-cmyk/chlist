import os
import json
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

# 안드로이드 전용 권한 및 도구
if platform == 'android':
    from android.permissions import request_permissions, Permission
    from android import api_version

# 한글 폰트 설정 (font.ttf 파일이 앱 폴더에 있어야 함)
FONT_NAME = "font.ttf"
if os.path.exists(FONT_NAME):
    LabelBase.register(name="Roboto", fn_regular=FONT_NAME)

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
        app = App.get_running_app()
        rv_data = app.root.ids.rv.data[self.index]
        
        if checkbox_type == 'complete':
            rv_data['complete'] = not self.complete
            if rv_data['complete']:
                rv_data['shortage'], rv_data['rework'] = False, False
        elif checkbox_type == 'shortage':
            rv_data['shortage'] = not self.shortage
            if rv_data['shortage']:
                rv_data['complete'], rv_data['rework'] = False, False
        elif checkbox_type == 'rework':
            rv_data['rework'] = not self.rework
            if rv_data['rework']:
                rv_data['complete'], rv_data['shortage'] = False, False
        
        app.root.ids.rv.refresh_from_data()

    def open_pdf(self):
        app = App.get_running_app()
        if not app.pdf_folder_path: return
        pdf_path = os.path.join(app.pdf_folder_path, f"{self.item_code}.pdf")
        
        if not os.path.exists(pdf_path):
            Popup(title="오류", content=Label(text="파일이 없습니다."), size_hint=(0.6, 0.3)).open()
            return

        if platform == 'android':
            try:
                from jnius import autoclass, cast
                PythonActivity = autoclass('org.kivy.android.PythonActivity')
                Intent = autoclass('android.content.Intent')
                Uri = autoclass('android.net.Uri')
                File = autoclass('java.io.File')
                StrictMode = autoclass('android.os.StrictMode')
                
                # Android 7.0+ FileUriExposedException 방지
                StrictMode.disableDeathOnFileUriExposure()
                
                file = File(pdf_path)
                uri = Uri.fromFile(file)
                intent = Intent(Intent.ACTION_VIEW)
                intent.setDataAndType(uri, "application/pdf")
                intent.setFlags(Intent.FLAG_ACTIVITY_NO_HISTORY | Intent.FLAG_GRANT_READ_URI_PERMISSION)
                
                currentActivity = cast('android.app.Activity', PythonActivity.mActivity)
                currentActivity.startActivity(intent)
            except Exception as e:
                print(f"PDF Open Error: {e}")
        else:
            if os.name == 'nt': os.startfile(pdf_path)
            else: subprocess.run(['xdg-open', pdf_path])

class CheckSheetRV(RecycleView):
    pass

class RootWidget(BoxLayout):
    pass

class CheckSheetApp(App):
    excel_path = StringProperty('')
    pdf_folder_path = StringProperty('')

    def build(self):
        if platform == 'android':
            self.request_android_permissions()
        self.load_settings()
        return RootWidget()

    def request_android_permissions(self):
        permissions = [Permission.READ_EXTERNAL_STORAGE, Permission.WRITE_EXTERNAL_STORAGE]
        if api_version >= 33:
            # Android 13 이상에서 파일 접근을 위해 필요한 경우 추가 권한 요청
            # 엑셀/PDF 파일 접근을 위해 MANAGE_EXTERNAL_STORAGE가 필요할 수 있음
            pass
        request_permissions(permissions)

    def on_start(self):
        if self.excel_path and os.path.exists(self.excel_path):
            self.load_excel_data(self.excel_path)

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
        start_path = "/sdcard" if platform == 'android' else os.getcwd()
        file_chooser = FileChooserListView(path=start_path)
        if mode == 'dir': file_chooser.dirselect = True
        
        content = BoxLayout(orientation='vertical')
        popup = Popup(title="선택", content=content, size_hint=(0.9, 0.9))
        
        def on_select(instance):
            if file_chooser.selection:
                path = file_chooser.selection[0]
                if mode == 'file':
                    self.excel_path = path
                    self.load_excel_data(path)
                else: self.pdf_folder_path = path
                self.save_settings()
            popup.dismiss()

        btn_layout = BoxLayout(size_hint_y=None, height=40)
        select_btn = Button(text="선택")
        select_btn.bind(on_release=on_select)
        cancel_btn = Button(text="취소")
        cancel_btn.bind(on_release=popup.dismiss)
        content.add_widget(file_chooser)
        btn_layout.add_widget(select_btn)
        btn_layout.add_widget(cancel_btn)
        content.add_widget(btn_layout)
        popup.open()

    def load_excel_data(self, path):
        try:
            wb = load_workbook(path, data_only=True)
            ws = wb.active
            rows = list(ws.rows)
            if not rows: return
            
            headers = [str(cell.value).strip().lower() for cell in rows[0]]
            try:
                idx_no = headers.index('no')
                idx_code = headers.index('품목코드')
                idx_qty = headers.index('수량')
            except ValueError:
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
        except: pass

    def save_to_excel(self):
        if not self.root.ids.rv.data or not self.excel_path: return
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
            Popup(title="성공", content=Label(text="저장되었습니다."), size_hint=(0.4, 0.2)).open()
        except: pass

if __name__ == '__main__':
    CheckSheetApp().run()
