config system
	option hostname 'xxx'
	option timezone 'UTC-5'

config timeserver 'ntp'
	list server '0.ru.pool.ntp.org'
	list server '1.ru.pool.ntp.org'
	list server '2.ru.pool.ntp.org'
	list server '3.ru.pool.ntp.org'
	option enabled '0'
	option enable_server '0'

config led 'led_usb'
	option name 'USB'
	option sysfs 'tp-link:green:usb'
	option trigger 'usbdev'
	option dev '1-1'
	option interval '50'

config led 'led_wlan'
	option name 'WLAN'
	option sysfs 'tp-link:green:wlan'
	option trigger 'phy0tpt'

