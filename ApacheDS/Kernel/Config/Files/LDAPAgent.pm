# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Config::Files::LDAPAgent;

use strict;
use warnings;
no warnings 'redefine';    ## no critic
use utf8;

use vars (qw($Self));

sub Load {
    my ( $File, $Self ) = @_;

    # --------------------------------------------------- #
    # authentication settings                             #
    # (enable what you need, auth against LDAP directory  #
    # --------------------------------------------------- #
    # This is an example configuration for an LDAP auth. backend.
    # (take care that Net::LDAP is installed!)
    $Self->{'AuthModule1'}               = 'Kernel::System::Auth::LDAP';
    $Self->{'AuthModule::LDAP::Host1'}   = 'localhost';
    $Self->{'AuthModule::LDAP::BaseDN1'} = 'ou=users,o=force';
    $Self->{'AuthModule::LDAP::UID1'}    = 'uid';

    # Check if the user is allowed to auth in a posixGroup
    # (e. g. user needs to be in a group xyz to use otrs)
    #  $Self->{'AuthModule::LDAP::GroupDN'} = 'cn=otrsallow,ou=posixGroups,dc=example,dc=com';
    #    $Self->{'AuthModule::LDAP::AccessAttr'} = 'memberUid';
    # for ldap posixGroups objectclass (just uid)
    #    $Self->{'AuthModule::LDAP::UserAttr'} = 'UID';
    # for non ldap posixGroups objectclass (with full user dn)
    #    $Self->{'AuthModule::LDAP::UserAttr'} = 'DN';

    # The following is valid but would only be necessary if the
    # anonymous user do NOT have permission to read from the LDAP tree
    #    $Self->{'AuthModule::LDAP::SearchUserDN'} = '';
    #    $Self->{'AuthModule::LDAP::SearchUserPw'} = '';

    # in case you want to add always one filter to each ldap query, use
    # this option. e. g. AlwaysFilter => '(mail=*)' or AlwaysFilter => '(objectclass=user)'
    # or if you want to filter with a locigal OR-Expression, like AlwaysFilter => '(|(mail=*abc.com)(mail=*xyz.com))'
    $Self->{'AuthModule::LDAP::AlwaysFilter1'} = '(objectclass=person)';

    # in case you want to add a suffix to each login name, then
    # you can use this option. e. g. user just want to use user but
    # in your ldap directory exists user@domain.
    #    $Self->{'AuthModule::LDAP::UserSuffix'} = '@domain.com';

    # In case you want to convert all given usernames to lower letters you
    # should activate this option. It might be helpfull if databases are
    # in use that do not distinguish selects for upper and lower case letters
    # (Oracle, postgresql). User might be synched twice, if this option
    # is not in use.
    #    $Self->{'AuthModule::LDAP::UserLowerCase'} = 0;

    # In case you need to use OTRS in iso-charset, you can define this
    # by using this option (converts utf-8 data from LDAP to iso).
    #    $Self->{'AuthModule::LDAP::Charset'} = 'iso-8859-1';

    # Net::LDAP new params (if needed - for more info see perldoc Net::LDAP)
    $Self->{'AuthModule::LDAP::Params1'} = {
        port    => 10389,
        timeout => 120,
        async   => 0,
        version => 3,
    };

    # --------------------------------------------------- #
    # authentication sync settings                        #
    # (enable agent data sync. after succsessful          #
    # authentication)                                     #
    # --------------------------------------------------- #
    # This is an example configuration for an LDAP auth sync. backend.
    # (take care that Net::LDAP is installed!)
    $Self->{'AuthSyncModule1'}               = 'Kernel::System::Auth::Sync::LDAP';
    $Self->{'AuthSyncModule::LDAP::Host1'}   = 'localhost';
    $Self->{'AuthSyncModule::LDAP::BaseDN1'} = 'ou=users,o=force';
    $Self->{'AuthSyncModule::LDAP::UID1'}    = 'uid';

    # The following is valid but would only be necessary if the
    # anonymous user do NOT have permission to read from the LDAP tree
    #    $Self->{'AuthSyncModule::LDAP::SearchUserDN'} = '';
    #    $Self->{'AuthSyncModule::LDAP::SearchUserPw'} = '';

    # in case you want to add always one filter to each ldap query, use
    # this option. e. g. AlwaysFilter => '(mail=*)' or AlwaysFilter => '(objectclass=user)'
    # or if you want to filter with a logical OR-Expression, like AlwaysFilter => '(|(mail=*abc.com)(mail=*xyz.com))'
    $Self->{'AuthSyncModule::LDAP::AlwaysFilter1'} = '(objectclass=person)';

    # AuthSyncModule::LDAP::UserSyncMap
    # (map if agent should create/synced from LDAP to DB after successful login)
    # you may specify LDAP-Fields as either
    #  * list, which will check each field. first existing will be picked ( ["givenName","cn","_empty"] )
    #  * name of an LDAP-Field (may return empty strings) ("givenName")
    #  * fixed strings, prefixed with an underscore: "_test", which will always return this fixed string
    $Self->{'AuthSyncModule::LDAP::UserSyncMap1'} = {

        # DB -> LDAP
        UserFirstname => 'givenName',
        UserLastname  => 'sn',
        UserEmail     => 'mail',
    };

    # In case you need to use OTRS in iso-charset, you can define this
    # by using this option (converts utf-8 data from LDAP to iso).
    #    $Self->{'AuthSyncModule::LDAP::Charset'} = 'iso-8859-1';

    # Net::LDAP new params (if needed - for more info see perldoc Net::LDAP)
    $Self->{'AuthSyncModule::LDAP::Params1'} = {
        port    => 10389,
        timeout => 120,
        async   => 0,
        version => 3,
    };

    # Die if backend can't work, e. g. can't connect to server.
    #    $Self->{'AuthSyncModule::LDAP::Die'} = 1;

    # Attributes needed for group syncs
    # (attribute name for group value key)
    $Self->{'AuthSyncModule::LDAP::AccessAttr1'} = 'uniquemember';

    # (attribute for type of group content UID/DN for full ldap name)
    #    $Self->{'AuthSyncModule::LDAP::UserAttr'} = 'UID';
    $Self->{'AuthSyncModule::LDAP::UserAttr1'} = 'DN';

    # AuthSyncModule::LDAP::UserSyncInitialGroups
    # (sync following group with rw permission after initial create of first agent
    # login)
    $Self->{'AuthSyncModule::LDAP::UserSyncInitialGroups1'} = [
        'users',
    ];

    # AuthSyncModule::LDAP::UserSyncGroupsDefinition
    # (If "LDAP" was selected for AuthModule and you want to sync LDAP
    # groups to otrs groups, define the following.)
    $Self->{'AuthSyncModule::LDAP::UserSyncGroupsDefinition1'} = {
        'cn=Sith Lords,ou=orders,ou=groups,o=force' => {    # LDAP  group.
            'admin' => {                                    # OTRS group.
                rw => 1,                                    # Effective permission.
                ro => 1,                                    # Effective permission.
            },

            # 'sithlords' => {      # This group does not exist in OTRS you need to create it in order to use it.
            #     rw => 1,
            #     ro => 1,
            # },
        },
        'cn=Night Sisters,ou=orders,ou=groups,o=force' => {
            'admin' => {
                rw => 1,
                ro => 1,
            },

            # 'nightsisters' => {
            #     rw => 1,
            #     ro => 1,
            # },
        },
        'cn=Knights of Ren,ou=orders,ou=groups,o=force' => {
            'admin' => {
                rw => 1,
                ro => 1,
            },

            # 'knightsofren' => {
            #     rw => 1,
            #     ro => 1,
            # },
        },
        'cn=Jedi Order,ou=orders,ou=groups,o=force' => {
            'admin' => {
                rw => 1,
                ro => 1,
            },

            # 'jediorder' => {
            #     rw => 1,
            #     ro => 1,
            # },
        },
    };

    # AuthSyncModule::LDAP::UserSyncRolesDefinition
    # (If "LDAP" was selected for AuthModule and you want to sync LDAP
    # groups to otrs roles, define the following.)
    $Self->{'AuthSyncModule::LDAP::UserSyncRolesDefinition1'} = {
        'cn=Sith Lords,ou=orders,ou=groups,o=force' => {    # LDAP  group.
            'sithlordsrole' => 1,    # OTRS role. (This role does not exists in OTRS, add it to get the results)
            'ldaprole'      => 0,    # OTRS role. (This role does not exists in OTRS, add it to get the results)
        },
        'cn=Night Sisters,ou=orders,ou=groups,o=force' => {

            # 'nightsistersrole' => 1,
        },
        'cn=Knights of Ren,ou=orders,ou=groups,o=force' => {

            # 'knightsofrenrole' => 1,
        },
        'cn=Jedi Order,ou=orders,ou=groups,o=force' => {

            # 'jediorderrole' => 1,
        },
    };

    # AuthSyncModule::LDAP::UserSyncAttributeGroupsDefinition
    # (If "LDAP" was selected for AuthModule and you want to sync LDAP
    # attributes to otrs groups, define the following.)
    #    $Self->{'AuthSyncModule::LDAP::UserSyncAttributeGroupsDefinition'} = {
    #        # ldap attribute
    #        'LDAPAttribute' => {
    #            # ldap attribute value
    #            'LDAPAttributeValue1' => {
    #                # otrs group
    #                'admin' => {
    #                    # permission
    #                    rw => 1,
    #                    ro => 1,
    #                },
    #                'faq' => {
    #                    rw => 0,
    #                    ro => 1,
    #                },
    #            },
    #        },
    #        'LDAPAttribute2' => {
    #            'LDAPAttributeValue' => {
    #                'users' => {
    #                    rw => 1,
    #                    ro => 1,
    #                },
    #            },
    #         }
    #    };

    # AuthSyncModule::LDAP::UserSyncAttributeRolesDefinition
    # (If "LDAP" was selected for AuthModule and you want to sync LDAP
    # attributes to otrs roles, define the following.)
    #    $Self->{'AuthSyncModule::LDAP::UserSyncAttributeRolesDefinition'} = {
    #        # ldap attribute
    #        'LDAPAttribute' => {
    #            # ldap attribute value
    #            'LDAPAttributeValue1' => {
    #                # otrs role
    #                'role1' => 1,
    #                'role2' => 1,
    #            },
    #        },
    #        'LDAPAttribute2' => {
    #            'LDAPAttributeValue1' => {
    #                'role3' => 1,
    #            },
    #        },
    #    };

    return;
}

1;
