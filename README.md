# openldap_setup_automated

This script will setup Openldap server, clients and will also add test user to test via Openldap.
This script is build irrespective of environment [ie. On-premises/Cloud]

Steps to execute:

1. Clone the repository

	$git clone https://github.com/shimpisagar/openldap_setup_automated.git
2. Modify "ldap.props" according to your environment
3. Execute below script to setup Openldap server and clients

	$./openldap_setup.sh
