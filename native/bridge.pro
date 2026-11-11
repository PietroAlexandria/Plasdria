QT += core qml network gui dbus concurrent
TEMPLATE = lib
CONFIG += plugin c++17
TARGET = plasdriaplugin
SOURCES += plugin.cpp dashboardclient.cpp chathistory.cpp mediaclient.cpp networkclient.cpp secretclient.cpp systemclient.cpp
HEADERS += dashboardclient.h chathistory.h mediaclient.h networkclient.h secretclient.h systemclient.h
DESTDIR = $$PWD/../package/contents/ui/bridge
