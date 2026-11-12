QT += core gui network dbus testlib
CONFIG += console testcase c++17
CONFIG -= app_bundle
TEMPLATE = app
TARGET = dashboardclient_test
SOURCES += dashboardclient_test.cpp ../native/dashboardclient.cpp
HEADERS += ../native/dashboardclient.h
