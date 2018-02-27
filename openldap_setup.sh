#!/bin/bash

LOC=`pwd`
PROP=ldap.props
source $LOC/$PROP

timestamp()
{
        echo "`date +%Y-%m-%d,%H:%M:%S`"
}


if [ -z $PVT_KEY ]
then
        echo -e "\033[32m`timestamp` \033[32mUsing Plain Password For Cluster Setup\033[0m"
        echo $PASSSWORD
        ssh_cmd="sshpass -p $SSH_SERVER_PASSWORD ssh"
        scp_cmd="sshpass -p $SSH_SERVER_PASSWORD scp"
else
        echo -e "\033[32m`timestamp` \033[32mUsing Private Key For Cluster Setup\033[0m"
        echo $PASSSWORD
                ssh_cmd="ssh -i $PVT_KEY"
                scp_cmd="scp -i $PVT_KEY"
        if [ -e $PVT_KEY ]
        then
                echo "File Exist" &> /dev/null
        else
                echo -e "\033[35mPrivate key is missing.. Please check!!!\033[0m"
                exit 1;
        fi
fi


openldap_server(){

echo -e  "\033[32m`timestamp` \033[32mInstalling Openldap Server Packages \033[0m"
yum install openldap-* mlocate migrationtools sshpass -y 2&>1 /dev/null
slappasswd=`slappasswd -s $OPENLDAP_SERVER_SLAPPASSWD`
sed -i 's/my-domain/lti/g' /etc/openldap/slapd.d/cn\=config/olcDatabase\=\{2\}hdb.ldif
echo "olcRootPW: $slappasswd" >> /etc/openldap/slapd.d/cn\=config/olcDatabase\=\{2\}hdb.ldif
/bin/sed -i 's/my-domain/lti/g' /etc/openldap/slapd.d/cn\=config/olcDatabase\=\{1\}monitor.ldif
/bin/updatedb
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown ldap:ldap -Rf /var/lib/ldap
systemctl start slapd
/bin/sed -i "s/ou=Group/ou=Groups/g" /usr/share/migrationtools/migrate_common.ph
/bin/sed -i 's/DEFAULT_MAIL_DOMAIN = "padl.com"/DEFAULT_MAIL_DOMAIN = "lti.com"/g' /usr/share/migrationtools/migrate_common.ph
/bin/sed -i 's/DEFAULT_BASE = "dc=padl,dc=com"/DEFAULT_BASE = "dc=lti,dc=com"/g' /usr/share/migrationtools/migrate_common.ph
/bin/sed -i 's/EXTENDED_SCHEMA = 0/EXTENDED_SCHEMA = 1/g' /usr/share/migrationtools/migrate_common.ph

echo -e  "\033[32m`timestamp` \033[32mSetting Up Test Users and Groups \033[0m"
#Create LDIF file for base users
mkdir /root/ldap/
/usr/share/migrationtools/migrate_base.pl >/root/ldap/base.ldif

#Create users,password and groups for LDAP user testing
mkdir /home/ldap
/usr/sbin/useradd -d /home/ldap/user1 user1
/usr/sbin/useradd -d /home/ldap/user2 user2
/usr/sbin/useradd -d /home/ldap/user3 user3

/usr/bin/echo -e "user1\nuser1" |(passwd --stdin user1)
/usr/bin/echo -e "user2\nuser2" |(passwd --stdin user2)
/usr/bin/echo -e "user3\nuser3" |(passwd --stdin user3)


/bin/getent passwd |tail -n 3   >/root/ldap/users
/bin/getent shadow |tail -n 3  >/root/ldap/passwords
/bin/getent group |tail -n 3   >/root/ldap/groups

#Create LDAP files for users
/usr/share/migrationtools/migrate_passwd.pl /root/ldap/users > /root/ldap/users.ldif
/usr/share/migrationtools/migrate_group.pl /root/ldap/groups > /root/ldap/groups.ldif

#Add schema
/bin/ldapadd -Y EXTERNAL -H ldapi:/// -D "cn=config" -f  /etc/openldap/schema/cosine.ldif
/bin/ldapadd -Y EXTERNAL -H ldapi:/// -D "cn=config" -f /etc/openldap/schema/nis.ldif
/bin/ldapadd  -Y EXTERNAL -H ldapi:// -f /etc/openldap/schema/inetorgperson.ldif

#Add data to ldap servers
echo -e  "\033[32m`timestamp` \033[32mAdding test users and groups to LDAP \033[0m"
/bin/ldapadd -x -w redhat -D "cn=Manager,dc=lti,dc=com" -f /root/ldap/base.ldif
/bin/ldapadd -x -w redhat -D "cn=Manager,dc=lti,dc=com" -f /root/ldap/users.ldif
/bin/ldapadd -x -w redhat -D "cn=Manager,dc=lti,dc=com" -f /root/ldap/groups.ldif


#Map users and groups
echo -e  "\033[32m`timestamp` \033[32mConfigure Users to Group Mappings \033[0m"
cat <<EOF >> /root/groupsmap1.ldif
dn: cn=user1,ou=Groups,dc=lti,dc=com
changetype: modify
add: memberUid
memberUid: user1
EOF

cat <<EOF >> /root/groupsmap2.ldif
dn: cn=user2,ou=Groups,dc=lti,dc=com
changetype: modify
add: memberUid
memberUid: user2
EOF

cat <<EOF >> /root/groupsmap3.ldif
dn: cn=user3,ou=Groups,dc=lti,dc=com
changetype: modify
add: memberUid
memberUid: user3
EOF

/bin/ldapmodify -D "cn=Manager,dc=lti,dc=com" -w redhat < /root/groupsmap1.ldif
/bin/ldapmodify -D "cn=Manager,dc=lti,dc=com" -w redhat < /root/groupsmap2.ldif
/bin/ldapmodify -D "cn=Manager,dc=lti,dc=com" -w redhat < /root/groupsmap3.ldif

#Removing test users created locally
/usr/sbin/userdel -r user1
/usr/sbin/userdel -r user2
/usr/sbin/userdel -r user3

echo -e  "\033[32m`timestamp` \033[32mOpenldap server setup completed successfully \033[0m"

}

openldap_clients(){


        for host in "${OPENLDAP_CLIENTS[@]}"
        do
                LDAP_CLIENT=`echo $host`
        #host_ip=`awk "/$host/{getline; print}"  $LOC/ambari.props|cut -d'=' -f 2`
        if [ "$SSH_USER" != "root" ]
        then
                wait
                $ssh_cmd  -o "StrictHostKeyChecking no" -o "CheckHostIP=no" -o "UserKnownHostsFile=/dev/null" $USER@$LDAP_CLIENT "sudo yum install openldap-clients openldap-devel nss-pam-ldapd pam_ldap authconfig authconfig-gtk openldap* -y 2&>1 /dev/null"
		wait
		$ssh_cmd  -o "StrictHostKeyChecking no" -o "CheckHostIP=no" -o "UserKnownHostsFile=/dev/null" $USER@$LDAP_CLIENT "sudo /sbin/authconfig  --enableldap --enableldapauth  --enablemkhomedir --ldapserver=ldap://$OPENLDAP_SERVER_HOSTNAME:389 --ldapbasedn="dc=lti,dc=com" --update"
		wait
		$ssh_cmd  -o "StrictHostKeyChecking no" -o "CheckHostIP=no" -o "UserKnownHostsFile=/dev/null" $USER@$LDAP_CLIENT "sudo systemctl restart nslcd &> /dev/null"
		echo -e  "\033[32m`timestamp` \033[32mOpenldap Client Setup Completed\033[0m"
		wait
        else
                wait
                $ssh_cmd  -o "StrictHostKeyChecking no" -o "CheckHostIP=no" -o "UserKnownHostsFile=/dev/null" $USER@$LDAP_CLIENT "yum install openldap-clients openldap-devel nss-pam-ldapd pam_ldap authconfig authconfig-gtk openldap* -y  2&>1 /dev/null"
		wait
		$ssh_cmd  -o "StrictHostKeyChecking no" -o "CheckHostIP=no" -o "UserKnownHostsFile=/dev/null" $USER@$LDAP_CLIENT "/sbin/authconfig  --enableldap --enableldapauth  --enablemkhomedir --ldapserver=ldap://$OPENLDAP_SERVER_HOSTNAME:389 --ldapbasedn="dc=lti,dc=com" --update"
		wait
		$ssh_cmd  -o "StrictHostKeyChecking no" -o "CheckHostIP=no" -o "UserKnownHostsFile=/dev/null" $USER@$LDAP_CLIENT "systemctl restart nslcd &> /dev/null"
        fi
        done

}

openldap_server
openldap_clients
