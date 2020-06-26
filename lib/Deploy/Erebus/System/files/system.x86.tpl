config system
	option hostname 'xxx'
	option timezone 'UTC-5'
	option ttylogin '0'
	option log_size '64'
	option urandom_seed '0'

config timeserver 'ntp'
	list server '0.ru.pool.ntp.org'
	list server '1.ru.pool.ntp.org'
	list server '2.ru.pool.ntp.org'
	list server '3.ru.pool.ntp.org'
	option enabled '0'
	option enable_server '0'

