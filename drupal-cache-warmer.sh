#!/bin/sh

export DISPLAY=:0

/usr/local/bin/wget -q http://btully.dyndns.org/sitemap.xml --no-cache -O - | egrep -o "https://btully.dyndns.org[^<]+" | /usr/local/bin/wget --header "Cookie: has_js=1" -U "cachewarmer" -q -i - -O /dev/null --wait 1