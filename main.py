from kivy.app import App
from kivy.uix.label import Label

class Step2_3App(App):
    def build(self):
        try:
            # pysmb 로드 시도
            import smb
            from smb.SMBConnection import SMBConnection
            return Label(text='Step 2-3: pysmb Load Success')
        except Exception as e:
            return Label(text=f'Step 2-3 Error: {str(e)}')

if __name__ == '__main__':
    Step2_3App().run()
