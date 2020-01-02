# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Config::Files::LDAPCustomer;
use strict;
use warnings;
no warnings 'redefine';    ## no critic
use utf8;

use vars (qw($Self));

sub Load {
    my ( $File, $Self ) = @_;

    # --------------------------------------------------- #
    # customer authentication settings                    #
    # (enable what you need, auth against LDAP directory  #
    # --------------------------------------------------- #
    # This is an example configuration for an LDAP auth. backend.
    # (take care that Net::LDAP is installed!)
    $Self->{'Customer::AuthModule1'}               = 'Kernel::System::CustomerAuth::LDAP';
    $Self->{'Customer::AuthModule::LDAP::Host1'}   = 'localhost';
    $Self->{'Customer::AuthModule::LDAP::BaseDN1'} = 'ou=users,o=force';
    $Self->{'Customer::AuthModule::LDAP::UID1'}    = 'uid';

    # Check if the user is allowed to auth in a posixGroup
    # (e. g. user needs to be in a group xyz to use otrs)
    #    $Self->{'Customer::AuthModule::LDAP::GroupDN'} = 'cn=otrsallow,ou=posixGroups,dc=example,dc=com';
    #    $Self->{'Customer::AuthModule::LDAP::AccessAttr'} = 'memberUid';
    # for ldap posixGroups objectclass (just uid)
    #    $Self->{'Customer::AuthModule::LDAP::UserAttr'} = 'UID';
    # for non ldap posixGroups objectclass (full user dn)
    #    $Self->{'Customer::AuthModule::LDAP::UserAttr'} = 'DN';

    # The following is valid but would only be necessary if the
    # anonymous user do NOT have permission to read from the LDAP tree
    #    $Self->{'Customer::AuthModule::LDAP::SearchUserDN'} = '';
    #    $Self->{'Customer::AuthModule::LDAP::SearchUserPw'} = '';

    # in case you want to add always one filter to each ldap query, use
    # this option. e. g. AlwaysFilter => '(mail=*)' or AlwaysFilter => '(objectclass=user)'
    $Self->{'Customer::AuthModule::LDAP::AlwaysFilter1'} = '(objectclass=person)';

    # in case you want to add a suffix to each customer login name, then
    # you can use this option. e. g. user just want to use user but
    # in your ldap directory exists user@domain.
    #    $Self->{'Customer::AuthModule::LDAP::UserSuffix'} = '@domain.com';

    # Net::LDAP new params (if needed - for more info see perldoc Net::LDAP)
    $Self->{'Customer::AuthModule::LDAP::Params1'} = {
        port    => 10389,
        timeout => 120,
        async   => 0,
        version => 3,
    };

    # Die if backend can't work, e. g. can't connect to server.
    #    $Self->{'Customer::AuthModule::LDAP::Die'} = 1;

    # --------------------------------------------------- #
    #                                                     #
    #             Start of config options!!!              #
    #                 CustomerUser stuff                  #
    #                                                     #
    # --------------------------------------------------- #
    # CustomerUser
    # (customer user ldap backend and settings)
    $Self->{CustomerUser1} = {
        Name   => 'LDAP Backend',
        Module => 'Kernel::System::CustomerUser::LDAP',
        Params => {

            # ldap host
            Host => 'localhost',

            # ldap base dn
            BaseDN => 'ou=users,o=force',

            # search scope (one|sub)
            SSCOPE => 'sub',

            # The following is valid but would only be necessary if the
            # anonymous user does NOT have permission to read from the LDAP tree
            #            UserDN => '',
            #            UserPw => '',
            # in case you want to add always one filter to each ldap query, use
            # this option. e. g. AlwaysFilter => '(mail=*)' or AlwaysFilter => '(objectclass=user)'
            AlwaysFilter => '(objectclass=person)',

            # if the charset of your ldap server is iso-8859-1, use this:
            # SourceCharset => 'iso-8859-1',
            # die if backend can't work, e. g. can't connect to server
            #            Die => 0,
            # Net::LDAP new params (if needed - for more info see perldoc Net::LDAP)
            Params => {
                port    => 10389,
                timeout => 120,
                async   => 0,
                version => 3,
            },
        },
        ReadOnly => 1,

        # customer unique id
        CustomerKey => 'uid',

        # customer #
        CustomerID                         => 'mail',
        CustomerUserListFields             => [ 'cn', 'mail' ],
        CustomerUserSearchFields           => [ 'cn', 'givenname', 'mail' ],
        CustomerUserSearchPrefix           => '',
        CustomerUserSearchSuffix           => '*',
        CustomerUserSearchListLimit        => 250,
        CustomerUserPostMasterSearchFields => ['mail'],
        CustomerUserNameFields             => [ 'givenname', 'sn' ],

        # show now own tickets in customer panel, CompanyTickets
        CustomerUserExcludePrimaryCustomerID => 0,

        # add a ldap filter for valid users (expert setting)
        #        CustomerUserValidFilter => '(!(description=gesperrt))',
        # admin can't change customer preferences
        AdminSetPreferences => 0,

        # cache time to live in sec. - cache any ldap queries
        CacheTTL => 120,
        Map      => [

            # note: Login, Email and CustomerID are mandatory!
            # if you need additional attributes from AD, just map them here.
            # var, frontend, storage, shown (1=always,2=lite), required, storage-type, http-link, readonly
            # [ 'UserSalutation', 'Title',      'title',           1, 0, 'var', '', 0 ],
            [ 'UserFirstname',  'Firstname',  'givenname', 1, 1, 'var', '', 0 ],
            [ 'UserLastname',   'Lastname',   'sn',        1, 1, 'var', '', 0 ],
            [ 'UserLogin',      'Username',   'uid',       1, 1, 'var', '', 0 ],
            [ 'UserEmail',      'Email',      'mail',      1, 1, 'var', '', 0 ],
            [ 'UserCustomerID', 'Department', 'mail',      0, 1, 'var', '', 0 ],

            # [ 'UserCustomerIDs', 'CustomerIDs', 'second_customer_ids', 1, 0, 'var', '', 0 ],
            # [ 'UserPhone',      'Phone',      'telephoneNumber', 1, 0, 'var', '', 0 ],
            # [ 'UserAddress',    'Address',    'postaladdress',   1, 0, 'var', '', 0 ],
            # [ 'UserComment',    'Comment',    'description',     1, 0, 'var', '', 0 ],
            # [ 'UserMobile',     'Mobile',      'mobile', 1, 0, 'var', '', 0 ],
            # [ 'UserRoom',       'Room',        'physicalDeliveryOfficeName', 1, 0, 'var', '', 0 ],
        ],
    };

    return;
}

1;
