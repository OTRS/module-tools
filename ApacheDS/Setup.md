# Setup and configure a basic LDAP server to use with OTRS

1. Download and Install Apache Directory Studio

2. Create a new LDAP server
    Choose:      Apache Software Foundation -> ApacheDS
    Server Name: Force Users

3. Edit server by double click the server name
    1. Go to Partitions tab and click add

        ```
        Partition General Details
        Type:   JDBM
        ID:     Force
        Suffix: o=force

        Synchronization on write

        Auto-generate context entry from suffix DN

        Enable Optimizer
        ```

    2. Note: leave all other settings as default including the server ports
    3. Click on save button (from the tool bar)

4. Start the server

5. Create new connection
    1. Network Parameter

        ```
        Connection name: Force Users
        Hostname:        localhost
        Port:            10389
        ```

    2. click on Next button

    3. Authentication

        ```
        Authentication Method: No Authentication
        ```

    4. Finish

6. Import users and groups
    1. Right click o=force
    2. Import
    3. Choose the ForceUsers.ldif file

7. Prepare OTRS
    1. Copy LDAPAgent.pm and LDAPCustomer.pm to Kernel/Config/Files/*