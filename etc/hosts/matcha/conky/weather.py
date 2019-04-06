import requests
import json
import datetime

TOKEN = "20a82c94f0875c3c96d87e5e28c03a58"
CITY = "1859088"  # Koganei-city, Tokyo

class Weather:
    def __init__(self, token=None, city=None):
        endpoint_tpl = "http://api.openweathermap.org/data/2.5/forecast?units=metric&id={city}&APPID={token}"
        self.endpoint = endpoint_tpl.format(token=token, city=city)

    def update(self):
        self.rawdata = requests.get(self.endpoint).json()
        return self.rawdata

    def get_three_days(self, exportfile=False):
        data = self.update()
        dt_now = datetime.datetime.now()
        three_days = [dt_now + datetime.timedelta(days=i+1) for i in range(3)]

        dt_txt_tpl = '{year}-{month}-{day} 12:00:00'
        dt_txt_three_days = [dt_txt_tpl.format(year=d.year, month=str(d.month).zfill(2), day=str(d.day).zfill(2)) for d in three_days]
        self.forecasts = [f for f in data['list'] if f['dt_txt'] in dt_txt_three_days]
        return self.forcasts

if __name__ == '__main__':
    w = Weather(token=TOKEN, city=CITY)
    print(w.get_three_days())
