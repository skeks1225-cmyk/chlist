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
from kivy.properties import StringProperty, BooleanProperty, NumericProperty, DictProperty, ObjectProperty
from kivy.uix.popup import Popup
from kivy.uix.filechooser import FileChooserListView
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.textinput import TextInput
from kivy.uix.scrollview import ScrollView
from kivy.uix.image import Image
from kivy.core.text import LabelBase
from kivy.utils import platform
from kivy.clock import Clock
from kivy.metrics import dp
from kivy.graphics.texture import Texture

# 안드로이드 키보드 설정
if platform == 'android':
    Window.softinput_mode = 'below_target'

# SMB 라이브러리
SMB_AVAILABLE = False
try:
    from smb.SMBConnection import SMBConnection
    SMB_AVAILABLE = True
except: pass

# 한글 폰트
try:
    FONT_NAME = "font.ttf"
    if os.path.exists(FONT_NAME):
        LabelBase.register(name="Roboto", fn_regular=FONT_NAME)
except: pass

SETTINGS_FILE = 'settings.json'
LOCAL_BASE = "/sdcard/Download/CheckSheet" if platform == 'android' else os.path.join(os.getcwd(), "CheckSheet_Data")
if not os.path.exists(LOCAL_BASE): os.makedirs(LOCAL_BASE)

class RowWidget(BoxLayout):
    no = StringProperty('')
    item_code = StringProperty('')
    quantity = StringProperty('')
    complete = BooleanProperty(False)
    shortage = BooleanProperty(False)
    rework = BooleanProperty(False)
    real_index = NumericProperty(0)

    def on_checkbox_active(self, checkbox_type):
        app = App.get_running_app()
        app.update_item_status(self.item_code, self.no, checkbox_type)

    def open_pdf(self):
        app = App.get_running_app()
        # 리스트에서 현재 항목의 인덱스를 찾아 뷰어 실행
        for i, d in enumerate(app.root.ids.rv.data):
            if d['item_code'] == self.item_code and d['no'] == self.no:
                app.open_pdf_viewer(i)
                break

class CheckSheetRV(RecycleView):
    pass

class RootWidget(BoxLayout):
    pass

class CheckSheetApp(App):
    excel_path = StringProperty('')
    pdf_folder_path = StringProperty('')
    pdf_source = StringProperty('local')
    excel_source = StringProperty('local')
    smb_config = DictProperty({'ip': '', 'user': '', 'pass': ''})
    
    # 뷰어 관련
    current_view_idx = NumericProperty(-1)
    viewer_visible = BooleanProperty(False)
    touch_start_x = NumericProperty(0)

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
                request_permissions([Permission.READ_EXTERNAL_STORAGE, Permission.WRITE_EXTERNAL_STORAGE, Permission.INTERNET, Permission.ACCESS_NETWORK_STATE])
                Env = autoclass('android.os.Environment')
                if not Env.isExternalStorageManager():
                    Context = autoclass('org.kivy.android.PythonActivity').mActivity
                    Intent = autoclass('android.content.Intent'); Settings = autoclass('android.provider.Settings'); Uri = autoclass('android.net.Uri')
                    intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                    uri = Uri.fromParts("package", Context.getPackageName(), None); intent.setData(uri)
                    Context.startActivity(intent)
            except: pass

    # --- 상태 동기화 핵심 로직 ---
    def update_item_status(self, item_code, no, status_type):
        data_list = self.root.ids.rv.data
        target_idx = -1
        for i, d in enumerate(data_list):
            if d['item_code'] == item_code and d['no'] == no:
                target_idx = i; break
        
        if target_idx != -1:
            d = data_list[target_idx]
            if status_type == 'complete':
                d['complete'] = not d['complete']
                if d['complete']: d['shortage'] = d['rework'] = False
            elif status_type == 'shortage':
                d['shortage'] = not d['shortage']
                if d['shortage']: d['complete'] = d['rework'] = False
            elif status_type == 'rework':
                d['rework'] = not d['rework']
                if d['rework']: d['complete'] = d['shortage'] = False
            
            self.root.ids.rv.refresh_from_data()
            # 만약 뷰어가 켜져 있다면 뷰어 UI도 갱신됨 (바인딩에 의해)

    # --- PDF 내장 뷰어 로직 ---
    def open_pdf_viewer(self, index):
        self.current_view_idx = index
        self.viewer_visible = True
        self.load_viewer_pdf()

    def close_viewer(self):
        self.viewer_visible = False

    def load_viewer_pdf(self):
        if self.current_view_idx < 0: return
        item = self.root.ids.rv.data[self.current_view_idx]
        item_code = item['item_code']
        
        local_path = os.path.join(LOCAL_BASE, f"{item_code}.pdf")
        
        # 로컬에 없으면 다운로드 시도 (SMB 모드인 경우)
        if not os.path.exists(local_path) and self.pdf_source == 'smb':
            self.download_pdf_silently(item_code)
            return # 다운로드 후 콜백에서 다시 호출됨

        if platform == 'android':
            self.render_pdf_to_widget(local_path)
        else:
            # PC에서는 그냥 외부 실행 (라이브러리 제약)
            if os.path.exists(local_path):
                if os.name == 'nt': os.startfile(local_path)
                else: subprocess.run(['xdg-open', local_path])

    def render_pdf_to_widget(self, path):
        # 안드로이드 네이티브 PdfRenderer 사용
        try:
            from jnius import autoclass
            File = autoclass('java.io.File')
            ParcelFileDescriptor = autoclass('android.os.ParcelFileDescriptor')
            PdfRenderer = autoclass('android.graphics.pdf.PdfRenderer')
            Bitmap = autoclass('android.graphics.Bitmap')
            
            f = File(path)
            if not f.exists(): 
                self.root.ids.pdf_img.source = ""
                return

            pfd = ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY)
            renderer = PdfRenderer(pfd)
            page = renderer.openPage(0) # 1페이지 로드
            
            # 해상도 조절 (화면 크기에 맞춤)
            w, h = page.getWidth() * 2, page.getHeight() * 2
            bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            page.render(bitmap, None, None, page.RENDER_MODE_FOR_DISPLAY)
            
            # 임시 파일로 저장하여 Kivy Image에 로드 (가장 안정적)
            tmp_img = os.path.join(LOCAL_BASE, "temp_view.png")
            FileOutputStream = autoclass('java.io.FileOutputStream')
            out = FileOutputStream(tmp_img)
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.close()
            page.close()
            renderer.close()
            
            self.root.ids.pdf_img.source = "" # 캐시 초기화
            self.root.ids.pdf_img.source = tmp_img
            self.root.ids.pdf_img.reload()
        except Exception as e:
            print(f"PDF Render Error: {e}")

    def download_pdf_silently(self, item_code):
        if not self.pdf_folder_path: return
        parts = self.pdf_folder_path.split("/", 1)
        share = parts[0]; sub = parts[1] if len(parts) > 1 else ""
        remote = os.path.join("/", sub, f"{item_code}.pdf").replace("\\", "/")
        local = os.path.join(LOCAL_BASE, f"{item_code}.pdf")
        
        def do_download(dt):
            try:
                conn = self.get_smb_conn_only()
                if conn:
                    with open(local, 'wb') as f: conn.retrieveFile(share, remote, f)
                    conn.close()
                    Clock.schedule_once(lambda x: self.load_viewer_pdf(), 0.1)
            except: pass
        Clock.schedule_once(do_download, 0.1)

    def get_smb_conn_only(self):
        try:
            ip = self.smb_config['ip']
            conn = SMBConnection(self.smb_config['user'], self.smb_config['pass'], "App", ip, use_ntlm_v2=True, is_direct_tcp=True)
            if conn.connect(ip, 445, timeout=3): return conn
        except: pass
        return None

    # --- 뷰어 내비게이션 (스와이프) ---
    def on_viewer_touch_down(self, touch):
        if self.viewer_visible:
            self.touch_start_x = touch.x

    def on_viewer_touch_up(self, touch):
        if self.viewer_visible:
            dx = touch.x - self.touch_start_x
            if abs(dx) > dp(100): # 100픽셀 이상 밀었을 때
                if dx > 0: # 오른쪽으로 밀기 -> 이전 항목
                    if self.current_view_idx > 0:
                        self.current_view_idx -= 1
                        self.load_viewer_pdf()
                else: # 왼쪽으로 밀기 -> 다음 항목
                    if self.current_view_idx < len(self.root.ids.rv.data) - 1:
                        self.current_view_idx += 1
                        self.load_viewer_pdf()

    # --- 공통 유틸리티 ---
    def load_settings(self):
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, 'r', encoding='utf-8') as f:
                    d = json.load(f); self.excel_path = d.get('excel_path', '')
                    self.pdf_folder_path = d.get('pdf_folder_path', ''); self.pdf_source = d.get('pdf_source', 'local')
                    self.excel_source = d.get('excel_source', 'local'); self.smb_config = d.get('smb_config', {'ip':'','user':'','pass':''})
            except: pass

    def save_settings(self):
        with open(SETTINGS_FILE, 'w', encoding='utf-8') as f:
            json.dump({'excel_path': self.excel_path, 'pdf_folder_path': self.pdf_folder_path, 'pdf_source': self.pdf_source, 'excel_source': self.excel_source, 'smb_config': self.smb_config}, f, ensure_ascii=False)

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
            self.root.ids.rv.data = rv_data
        except: pass

    def save_to_excel(self):
        if not self.excel_path: return
        try:
            wb = load_workbook(self.excel_path); ws = wb.active; headers = [str(cell.value).strip().lower() for cell in ws[1]]
            cols = {'완료':-1,'수량부족':-1,'재작업':-1}
            for k in cols: 
                if k in headers: cols[k] = headers.index(k)+1
            for d in self.root.ids.rv.data:
                row_idx = d['real_index']+2
                if cols['완료']>0: ws.cell(row=row_idx, column=cols['완료']).value = 'V' if d['complete'] else ''
                if cols['수량부족']>0: ws.cell(row=row_idx, column=cols['수량부족']).value = 'V' if d['shortage'] else ''
                if cols['재작업']>0: ws.cell(row=row_idx, column=cols['재작업']).value = 'V' if d['rework'] else ''
            wb.save(self.excel_path); self.show_error_popup("저장 완료")
        except: pass

    def show_error_popup(self, msg):
        Popup(title="알림", content=Label(text=msg, halign='center'), size_hint=(0.8, 0.4)).open()

    # --- SMB 브라우저 (v1.9 유지) ---
    def select_source(self, mode):
        content = BoxLayout(orientation='vertical', padding=dp(20), spacing=dp(20))
        popup = Popup(title="파일 출처 선택", content=content, size_hint=(0.85, 0.5))
        def on_choice(choice):
            popup.dismiss()
            if choice == 'local':
                if mode == 'excel': self.open_local_browser('file')
                else: self.open_local_browser('dir')
            else: self.open_smb_shares_browser(mode)
        content.add_widget(Button(text="폰 저장소", on_release=lambda x: on_choice('local')))
        content.add_widget(Button(text="PC 공유폴더", on_release=lambda x: on_choice('smb')))
        popup.open()

    def open_smb_shares_browser(self, mode):
        ip = self.smb_config['ip']; conn = self.get_smb_conn_only()
        if not conn: self.show_error_popup("SMB 접속 실패"); return
        content = BoxLayout(orientation='vertical'); scroll = ScrollView(); list_box = BoxLayout(orientation='vertical', size_hint_y=None, spacing=dp(5))
        list_box.bind(minimum_height=list_box.setter('height')); scroll.add_widget(list_box)
        popup = Popup(title="공유폴더 선택", content=content, size_hint=(0.95, 0.95))
        try:
            for s in conn.listShares():
                if s.isSpecial or s.name.endswith('$'): continue
                btn = Button(text=f"📁 {s.name}", size_hint_y=None, height=dp(90))
                btn.bind(on_release=lambda b, s=s: self.open_smb_files_browser(conn, s.name, "/", mode, popup))
                list_box.add_widget(btn)
        except: pass
        content.add_widget(scroll); content.add_widget(Button(text="취소", size_hint_y=None, height=dp(80), on_release=lambda x: popup.dismiss()))
        popup.open()

    def open_smb_files_browser(self, conn, share, path, mode, parent):
        content = BoxLayout(orientation='vertical'); scroll = ScrollView(); list_box = BoxLayout(orientation='vertical', size_hint_y=None, spacing=dp(2))
        list_box.bind(minimum_height=list_box.setter('height')); scroll.add_widget(list_box)
        popup = Popup(title=f"SMB: {share}{path}", content=content, size_hint=(0.95, 0.95))
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
                if mode == 'dir': self.pdf_folder_path = f"{share}{new_p}"; self.pdf_source='smb'; self.save_settings(); popup.dismiss(); parent.dismiss(); conn.close()
                else: refresh(new_p)
            else:
                if mode == 'file':
                    local = os.path.join(LOCAL_BASE, f.filename)
                    with open(local, 'wb') as lf: conn.retrieveFile(share, new_p, lf)
                    self.excel_path = local; self.excel_source='smb'; self.load_excel_data(local); self.save_settings(); popup.dismiss(); parent.dismiss(); conn.close()
        refresh(path); content.add_widget(scroll); content.add_widget(Button(text="닫기", size_hint_y=None, height=dp(80), on_release=lambda x: popup.dismiss()))
        popup.open()

    def open_local_browser(self, mode):
        start_p = "/sdcard" if platform == 'android' else os.getcwd()
        content = BoxLayout(orientation='vertical'); fc = FileChooserListView(path=start_p)
        if mode == 'dir': fc.dirselect = True
        popup = Popup(title="파일 선택", content=content, size_hint=(0.95, 0.95))
        def on_select(instance):
            if fc.selection:
                path = fc.selection[0]
                if mode == 'file': self.excel_path = path; self.excel_source='local'; self.load_excel_data(path)
                else: self.pdf_folder_path = path; self.pdf_source='local'
                self.save_settings(); popup.dismiss()
        content.add_widget(fc); content.add_widget(Button(text="선택 완료", size_hint_y=None, height=dp(70), on_release=on_select))
        popup.open()

    def open_smb_settings(self):
        scroll = ScrollView(size_hint=(1, 1))
        content = BoxLayout(orientation='vertical', padding=dp(20), spacing=dp(20), size_hint_y=None)
        content.bind(minimum_height=content.setter('height'))
        inputs = {}
        fields = [('ip', 'IP 주소'), ('user', 'ID (계정)'), ('pass', 'PW (비번)')]
        for key, hint in fields:
            content.add_widget(Label(text=hint, size_hint_y=None, height=dp(40), halign='left', text_size=(Window.width*0.85, None)))
            ti = TextInput(text=self.smb_config.get(key, ''), multiline=False, size_hint_y=None, height=dp(100), font_size='22sp')
            if key == 'pass': ti.password = True
            content.add_widget(ti); inputs[key] = ti
        popup = Popup(title="SMB 설정", content=scroll, size_hint=(0.95, 0.9))
        scroll.add_widget(content)
        def save(instance):
            self.smb_config = {k: v.text.strip() for k, v in inputs.items()}; self.save_settings(); popup.dismiss()
        content.add_widget(Button(text="저장", size_hint_y=None, height=dp(90), on_release=save, background_color=(0, 0.6, 0.8, 1)))
        popup.open()

if __name__ == '__main__':
    CheckSheetApp().run()
