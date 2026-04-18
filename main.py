from kivy.app import App
from kivy.uix.label import Label

class Step1App(App):
    def build(self):
        return Label(text='Step 1: Minimal Execution Success')

if __name__ == '__main__':
    Step1App().run()
