from kivy.app import App
from kivy.uix.label import Label
from kivy.clock import Clock
from kivy.utils import platform

class Step3App(App):
    def build(self):
        self.lbl = Label(text='Step 3: Waiting 2 seconds...')
        return self.lbl

    def on_start(self):
        if platform == 'android':
            # 앱이 완전히 켜진 2초 뒤에 WebView 클래스 로드 시도
            Clock.schedule_once(self.test_webview_load, 2)

    def test_webview_load(self, dt):
        try:
            from jnius import autoclass
            # WebView 관련 클래스들을 하나씩 불러봅니다.
            WebView = autoclass('android.webkit.WebView')
            self.lbl.text = 'Step 3: WebView Class Load Success!'
        except Exception as e:
            self.lbl.text = f'Step 3 Error: {str(e)}'

if __name__ == '__main__':
    Step3App().run()
