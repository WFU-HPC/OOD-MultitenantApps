[![DOI](https://zenodo.org/badge/1066655982.svg)](https://doi.org/10.5281/zenodo.18500730)

# Multitenant Apps: LLMs, Databases, Dashboards, and other shared services within Open OnDemand

**Wake Forest University**<br>
**The HPC Team** (https://hpc.wfu.edu)<br>
**Principal contact: Sean Anderson** (anderss@wfu.edu)

[Tips and Tricks Presentation from Oct. 2, 2025](https://github.com/WFU-HPC/OOD-MultitenantApps/blob/main/presentation.pdf)<br>
[Video Recording of the Presentation with Demos](https://drive.google.com/file/d/1aHcIRVxz4xpamuEcX_12sOG7OCYVNlBe/view?usp=sharing)

The Multitenant Apps framework was developed for supporting LLMs, databases, and other services on traditional, job-based HPC infrastructure through Open OnDemand (OOD). It allows for controlled and secure sharing of these services between select users, and can greatly reduce hardware overhead since users share the same resources. It is also an effective method for delivering content to users within the OOD interface, which is especially useful within classrooms, research groups, and even departments.


## Disclaimer

This software comes with no warranty. Make sure to use your "development" OOD server for testing, and make backups of any config or installation files as needed. For the Slurm WCKeys, you should test first without making any changes to your Slurm config files.


## Installation on OOD Server

I will assume that you have cloned the repo on your OOD dev server, and are working out of the root of this directory. You will need Root privileges for most of these commands, so take appropriate measures beforehand.

To get started, add this variable to your `/etc/ood/config/apps/dashboard/env` file:

```sh
MULTITENANT_ENABLE=false
```

Anything other than `true` will bypass the initializer, so this is just for safety while we put everything in place.

Copy the initializer to the correct location:

```sh
cp ./initializer/multitenant.rb /etc/ood/config/apps/dashboard/initializers/multitenant.rb
```

Now you need to copy all of the apps to the OOD system apps directory. If you are going to use a POSIX group to restrict their access, you will need to put the correct ownership and permissions now. In this example, I will use the `mtUsr` POSIX group as the group owner:

```sh
# copy
## Clients
cp -r ./apps-clients/multitenant-gradio              /var/www/ood/apps/sys/multitenant-gradio
cp -r ./apps-clients/multitenant-jupyter             /var/www/ood/apps/sys/multitenant-jupyter
## Delivery
cp -r ./apps-delivery/multitenant-delivery_debug     /var/www/ood/apps/sys/multitenant-delivery_debug
cp -r ./apps-delivery/multitenant-delivery_default   /var/www/ood/apps/sys/multitenant-delivery_default
cp -r ./apps-delivery/multitenant-delivery_readfile  /var/www/ood/apps/sys/multitenant-delivery_readfile
## Services
cp -r ./apps-services/multitenant-dashboard          /var/www/ood/apps/sys/multitenant-dashboard
cp -r ./apps-services/multitenant-database           /var/www/ood/apps/sys/multitenant-database
cp -r ./apps-services/multitenant-instruction        /var/www/ood/apps/sys/multitenant-instruction
cp -r ./apps-services/multitenant-llm                /var/www/ood/apps/sys/multitenant-llm

# ownership
## Clients
chown -R root:mtUsr /var/www/ood/apps/sys/multitenant-gradio
chown -R root:mtUsr /var/www/ood/apps/sys/multitenant-jupyter
## Delivery
chown -R root:mtUsr /var/www/ood/apps/sys/multitenant-delivery_debug
chown -R root:mtUsr /var/www/ood/apps/sys/multitenant-delivery_default
chown -R root:mtUsr /var/www/ood/apps/sys/multitenant-delivery_readfile
## Services
chown -R root:mtUsr /var/www/ood/apps/sys/multitenant-dashboard
chown -R root:mtUsr /var/www/ood/apps/sys/multitenant-database
chown -R root:mtUsr /var/www/ood/apps/sys/multitenant-instruction
chown -R root:mtUsr /var/www/ood/apps/sys/multitenant-llm

# permissions
## Clients
chmod 755 /var/www/ood/apps/sys/multitenant-gradio
chmod 755 /var/www/ood/apps/sys/multitenant-jupyter
## Delivery
chmod 755 /var/www/ood/apps/sys/multitenant-delivery_debug
chmod 755 /var/www/ood/apps/sys/multitenant-delivery_default
chmod 755 /var/www/ood/apps/sys/multitenant-delivery_readfile
## Services
chmod 750 /var/www/ood/apps/sys/multitenant-dashboard
chmod 750 /var/www/ood/apps/sys/multitenant-database
chmod 750 /var/www/ood/apps/sys/multitenant-instruction
chmod 750 /var/www/ood/apps/sys/multitenant-llm
```

Make sure that everything looks good on both the filesystem and in your OOD dashboard. Only users in the `mtUsr` group should be able to see the four "service" apps in their dashboard.


## Slurm WCKeys (IMPORTANT!)

We use `multitenant` for the WCKey. This value is arbitrary and you can use whatever you want! Just make sure to change it in both the initializer and in the `submit.yml.erb` files of the Multitenant apps (services).

This guide assumes that you do not currently have WCKeys enabled or used on your HPC system. If you are already using them -- you don't need any help from me!

The [documentation on the WCKeys is sparse](https://slurm.schedmd.com/wckey.html), to say the least. All you need to know is that we use WCKeys as both a way to:

1. **FILTER** the Multitenant jobs out of the queue, and also as a 
2. **SECURITY MEASURE** to restrict which users can even submit Multitenant jobs.

If you do not want to use them like point #2 above, then you do not need to modify your Slurm configuration at all. You can still submit jobs with an associated WCKey and Slurm will let you use all of the other commands to view those jobs.

If you do want to use them like point #2 above, then continue reading below.


### Enforcing WCKeys

You will need to add this to your `slurm.conf` file:

```
AccountingStorageEnforce=...,wckeys
TrackWCKey=yes
```

Note that you add `wckeys` to whatever values are already present in `AccountingStorageEnforce`. Next, add this to your `slurmdbd.conf` file:

```
TrackWCKey=yes
```

**WARNING:** Once those files have been edited, you will need to stop the `slurmctld` and `slurmdbd` services on your Slurm controller, and then start them again while monitoring their status and behavior. Once you confirm that everything is working as expected, you may have to restart `slurmd` on the rest of the cluster so that the new config can go into effect everywhere.


### Managing WCKeys

Get a list of all WCKeys currently in Slurm:

```sh
sacctmgr list wckey
```

Every **existing** user (that has submitted a job before) that submits a job without setting a WCKey gets two entries, one blank and one `*`.

You do not need to create WCKeys beforehand. Adding users to a WCKey will create it automatically, and removing all users from a WCKey will remove it from the list of active values. These tasks are easy to do, and take effect immediately:

```sh
sacctmgr add user hpcfaculty wckey=multitenant # to add a user to the multitenant wckey

sacctmgr del user hpcfaculty wckey=multitenant # to remove a user to the multitenant wckey
```

**WARNING:** new users, or users who have never submitted before, will **NOT** have any WCKey value associated with them. You will need to add them to a WCKey and give them a default:

```sh
sacctmgr add user <newuser> wckey=""
sacctmgr mod user <newuser> set defaultwckey=""
```

You can add these commands to your onboarding process.

## Enabling the Multitenant Framework

Once you have everything in place and are satisfied with your Slurm configuration, you will need to enable the Multitenant framework by chaning the environment variable in the `/etc/ood/config/apps/dashboard/env` file:

```sh
MULTITENANT_ENABLE=true
```

You will need to restart your PUN in order for this change to take effect.


## Using the Multitenant Framework

You really need at least two user accounts to properly test everything out, so grab a buddy or get a new test account! Remember, nothing will happen on the receiving user's side until they restart their PUN, so you will be well served to make a new button or link just for that.
