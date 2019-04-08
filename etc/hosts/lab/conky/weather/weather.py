#!/usr/bin/python3

import requests
import json
import datetime
import argparse

TOKEN = "20a82c94f0875c3c96d87e5e28c03a58"
noratoken = "9de243494c0b295cca9337e1e96b00e2"
CITY = "1850147"  # Tokyo
# CITY = "1859088"  # Koganei-city, Tokyo
# CITY = "1853677"  # Ota, Tokyo

SAVEFILE = '/home/mi/.cache/conky-weather/forecast.json'

class Weather:
    def __init__(self, token=TOKEN, city=CITY):
        endpoint_tpl = "http://api.openweathermap.org/data/2.5/forecast/daily?id={city}&units=metric&appid={token}"
        self.endpoint = endpoint_tpl.format(token=token, city=city)

    def update(self):
        self.rawdata = requests.get(self.endpoint).json()
        return self.rawdata

    def get_n_days(self, n=4, exportfile=False):
        data = self.update()
        dt_now = datetime.datetime.now()
        n_days_lst = [dt_now + datetime.timedelta(days=i+1) for i in range(n)]

        # dt_txt_tpl = '{year}-{month}-{day} 12:00:00'
        # dt_txt_n_days = [dt_txt_tpl.format(year=d.year, month=str(d.month).zfill(2), day=str(d.day).zfill(2)) for d in n_days_lst]
        # self.forecasts = [f for f in data['list'] if f['dt_txt'] in dt_txt_n_days]
        # self.forecasts = {
        #         i: f for i, f in enumerate([f for f in data['list'] if f['dt_txt'] in dt_txt_n_days])
        # }

        self.forecasts = data['list']

        if exportfile:
            with open(exportfile, 'w') as fd:
                json.dump(self.forecasts, fd)
        return self.forecasts

class Parser:
    def __init__(self, jsonfile=None):
        if jsonfile is None:
            jsonfile = SAVEFILE
        with open(jsonfile, 'r') as fd:
            self.forecasts = json.load(fd)

    def value(self, day, attr):
        forecast = self.forecasts[int(day)]
        if attr == 'weather_id':
            return forecast['weather'][0]['id']
        if attr == 'weather_name':
            return forecast['weather'][0]['main']
        if attr == 'weather_desc':
            return forecast['weather'][0]['description']
        if attr == 'humidity':
            return forecast['humidity']
        if attr == 'temp_morn':
            return round(forecast['temp']['morn'], 1)
        if attr == 'temp_day':
            return round(forecast['temp']['day'], 1)
        if attr == 'temp_eve':
            return round(forecast['temp']['eve'], 1)
        if attr == 'temp_night':
            return round(forecast['temp']['night'], 1)
        if attr == 'temp_min':
            return round(forecast['temp']['min'], 1)
        if attr == 'temp_max':
            return round(forecast['temp']['max'], 1)

    def calendar(self, day):
        dt_now = datetime.datetime.now()
        dt = dt_now + datetime.timedelta(days=int(day))
        # week = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        week = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
        # return "{month}/{day}".format(month=str(dt.month).zfill(2), day=str(dt.day).zfill(2))
        # return "{month}/{day}".format(month=str(dt.month), day=str(dt.day))
        return "{weekday}".format(weekday=week[dt.weekday()])
        # return "{weekday} ({month}/{day})".format(month=str(dt.month), day=str(dt.day), weekday=week[dt.weekday()])
        # return "{day}, {weekday}".format(day=str(dt.day).zfill(2), weekday=week[dt.weekday()])

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--update-weather', action='store_true')
    parser.add_argument('--parse', action='store_true')
    parser.add_argument('--calendar', action='store_true')
    parser.add_argument('--day')
    parser.add_argument('--attr')

    args = parser.parse_args()

    if args.update_weather:
        Weather(token=noratoken, city=CITY).get_n_days(exportfile=SAVEFILE)

    if args.calendar:
        out = Parser(jsonfile=SAVEFILE).calendar(args.day)
        print(out)

    if args.parse:
        out = Parser(jsonfile=SAVEFILE).value(args.day, args.attr)
        print(out)


