#!/bin/sh

# runit 服务模板
# 直接以前台方式运行内核，并把日志重定向到安装时指定的文件

exec placeholder_cmd_full >placeholder_log_file 2>&1
