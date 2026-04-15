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
        try:
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
        except: pass

    def open_pdf(self):
        try:
            app = App.get_running_app()
            if not app.pdf_folder_path: return
            pdf_path = os.path.join(app.pdf_folder_path, f"{self.item_code}.pdf")
            
            if not os.path.exists(pdf_path):
                app.show_error_popup(f"파일을 찾을 수 없습니다:\n{self.item_code}.pdf")
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
            App.get_running_app().show_error_popup(f"PDF 실행 오류:\n{str(e)}")

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
            error_layout = BoxLayout(orientation='vertical', padding=20)
            error_layout.add_widget(Label(text="CRITICAL ERROR", size_hint_y=None, height=50))
            error_layout.add_widget(Label(text=traceback.format_exc()))
            return error_layout

    def on_start(self):
        if platform == 'android':
            Clock.schedule_once(self.ask_permissions, 1)
        if self.excel_path and os.path.exists(self.excel_path):
            self.load_excel_data(self.excel_path)

    def ask_permissions(self, dt):
        try:
            from android.permissions import request_permissions, Permission
            request_permissions([
                Permission.READ_EXTERNAL_STORAGE,
                Permission.WRITE_EXTERNAL_STORAGE
            ])
        except: pass

    def show_error_popup(self, error_msg):
        Popup(title="알림", content=Label(text=error_msg), size_hint=(0.8, 0.4)).open()

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
        except Exception as e:
            self.show_error_popup(f"탐색기 오류:\n{e}")

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
        except Exception as e:
            self.show_error_popup(f"엑셀 로드 오류:\n{e}")

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
        except Exception as e:
            self.show_error_popup(f"저장 오류:\n{e}")

if __name__ == '__main__':
    CheckSheetApp().run()
