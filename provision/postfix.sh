#!/bin/sh

# shellcheck disable=1091
. mail-toaster.sh || exit

export JAIL_START_EXTRA=""
export JAIL_CONF_EXTRA=""

install_postfix()
{
	tell_status "installing postfix"
	stage_pkg_install postfix opendkim dialog4ports || exit
}

configure_opendkim()
{
	stage_sysrc milteropendkim_enable=YES
	stage_sysrc milteropendkim_cfgfile=/data/etc/opendkim.conf

	tell_status "See http://www.opendkim.org/opendkim-README"

	if [ ! -d "$STAGE_MNT/data/etc" ]; then mkdir "$STAGE_MNT/data/etc"; fi
	if [ ! -d "$STAGE_MNT/data/dkim" ]; then mkdir "$STAGE_MNT/data/dkim"; fi

	if [ -f "$STAGE_MNT/data/etc/opendkim.conf" ]; then
		echo "opendkim config retained"
		return
	fi

	sed \
		-e "/^Domain/ s/example.com/$TOASTER_DOMAIN/"  \
		-e "/^KeyFile/ s/\/.*$/\/data\/dkim\/$TOASTER_DOMAIN.private/"  \
		-e '/^Socket/ s/inet:port@localhost/inet:2016/' \
		-e "/^Selector/ s/my-selector-name/$(date '+%b%Y' | tr '[:upper:]' '[:lower:]')/" \
		"$STAGE_MNT/usr/local/etc/mail/opendkim.conf.sample" \
		> "$STAGE_MNT/data/etc/opendkim.conf"
}

configure_postfix()
{
	stage_sysrc postfix_enable=YES
	stage_exec postconf -e 'smtp_tls_security_level = may'

	if [ -n "$TOASTER_NRPE" ]; then
		stage_sysrc nrpe3_enable=YES
		stage_sysrc nrpe3_configfile="/data/etc/nrpe.cfg"
	fi

	for _f in master main
	do
		if [ -f "$ZFS_DATA_MNT/postfix/etc/$_f.cf" ]; then
			cp "$ZFS_DATA_MNT/postfix/etc/$_f.cf" "$STAGE_MNT/usr/local/etc/postfix/"
		fi
	done

	if [ -f "$ZFS_JAIL_MNT/postfix/etc/aliases" ]; then
		tell_status "preserving /etc/aliases"
		cp "$ZFS_JAIL_MNT/postfix/etc/aliases" "$STAGE_MNT/etc/aliases"
		stage_exec newaliases
	fi
}

start_postfix()
{
	tell_status "starting postfix"
	stage_exec service milter-opendkim start
	stage_exec service postfix start || exit
}

test_postfix()
{
	tell_status "testing opendkim"
	stage_test_running opendkim
	stage_listening 1026

	tell_status "testing postfix"
	stage_test_running master
	stage_listening 25
	echo "it worked."
}

base_snapshot_exists || exit
create_staged_fs postfix
start_staged_jail postfix
install_postfix
configure_postfix
start_postfix
test_postfix
promote_staged_jail postfix
