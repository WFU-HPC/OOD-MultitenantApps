# Multitenant Database App

**Wake Forest University**<br>
**The HPC Team** (https://hpc.wfu.edu)<br>
**Principal contact: Sean Anderson** (anderss@wfu.edu)

An app for sharing MySQL, MariaDB, or Postgres database server, within a Slurm job, with other users.

## MySQL

These are instructions to set up the classic "Sakila" SQL database example in MySQL.

First, load the software and set up your target directory where everything will go:

```sh
# load the module with sweet sweet mysql
module load apps/mysql/9.4.0

# convenient environment variable
export TARGET="/deac/inf/hpcGrp/examples"

# prep your desired data directory
mkdir -p ${TARGET}/data-mysql
chmod 750 ${TARGET}/data-mysql
```

Now you can initialize the database, and configure it with a new user and database name:

```sh
## create the init script, this is one single command
cat << EOF > ${TARGET}/init.sql
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13)';
CREATE USER 'deac'@'%' IDENTIFIED WITH caching_sha2_password BY 'godeacs';
GRANT ALL PRIVILEGES ON *.* TO 'deac'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
CREATE DATABASE sakila;
DROP USER 'root'@'localhost';
EOF

# initialize the database in the directory using the init file
mysqld --datadir=${TARGET}/data-mysql --initialize --init-file=${TARGET}/init.sql

# remove the now unneeded init file
rm ${TARGET}/init.sql
```

Let's download the Sakila DB files and uncompress them in the directory:

```sh
wget --no-check-certificate https://downloads.mysql.com/docs/sakila-db.tar.gz -O ${TARGET}/sakila-db.tar.gz
tar -xvf ${TARGET}/sakila-db.tar.gz -C $TARGET
```

Start up the MySQL server using some temporary host and port:

```sh
export MYSQL_HOST=0.0.0.0
export MYSQL_TCP_PORT=67504
export MYSQL_PWD=godeacs

mysqld --datadir=${TARGET}/data-mysql &
```

Now we are ready to load the Sakila content into our newly created database. Go ahead and log into the database:

```sh
cd $TARGET

mysql -h $MYSQL_HOST -P $MYSQL_TCP_PORT -u deac sakila
```

Run these commands whithin the database to load the schema and content:

```sql
SOURCE ./sakila-db/sakila-schema.sql;
SOURCE ./sakila-db/sakila-data.sql;
SHOW FULL TABLES;
\q
```

If everything went smoothly, you can now shut down the local database server:

```sh
mysqladmin -h $MYSQL_HOST -P $MYSQL_TCP_PORT -u deac shutdown
```

Lastly, remove the unneeded Sakila source files:

```sh
rm ${TARGET}/sakila-db.tar.gz
rm -r ${TARGET}/sakila-db
```

Your example DB is ready!


## MariaDB

First, load the software and set up your target directory where everything will go:

```sh
# load the module with sweet sweet mariadb
module load apps/mariadb/12.0.2

# convenient environment variable
export TARGET="/deac/inf/hpcGrp/examples"
```

Now you can initialize the database:

```sh
mariadb-install-db --auth-root-authentication-method=normal --basedir=$MARIADB_ROOT --datadir=${TARGET}/data-mariadb
chmod 750 ${TARGET}/data-mariadb
```

Let's download the Sakila DB files and uncompress them in the directory:

```sh
wget --no-check-certificate https://downloads.mysql.com/docs/sakila-db.tar.gz -O ${TARGET}/sakila-db.tar.gz
tar -xvf ${TARGET}/sakila-db.tar.gz -C $TARGET
```

Start up the MariaDB server using a temporary host and port:

```sh
export MYSQL_HOST=0.0.0.0
export MYSQL_TCP_PORT=67504
export MYSQL_PWD=godeacs
mariadbd --datadir=${TARGET}/data-mariadb &

mariadb-secure-installation --skip-ssl
```

Now we are ready to load the Sakila content into our newly created database. Go ahead and log into the database:

```sh
mariadb --skip-ssl -u root -p
```

Run these commands whithin the database to load the schema and content:

```sh
CREATE USER 'deac'@'%' IDENTIFIED BY 'godeacs';
GRANT ALL PRIVILEGES ON *.* TO 'deac'@'%' IDENTIFIED BY 'godeacs' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SELECT User, Host FROM mysql.user;
CREATE DATABASE sakila;
USE sakila;
SOURCE /deac/inf/hpcGrp/examples/sakila-db/sakila-schema.sql;
SOURCE /deac/inf/hpcGrp/examples/sakila-db/sakila-data.sql;
SHOW FULL TABLES;
\q
```

If everything went smoothly, you can now shut down the local database server:

```sh
mariadb-admin -u deac shutdown
```

Lastly, remove the unneeded Sakila source files:

```sh
rm ${TARGET}/sakila-db.tar.gz
rm -r ${TARGET}/sakila-db
```


## Postgres

First, load the software and set up your target directory and other environment variables:

```sh
# load the module with sweet sweet postgres
module load apps/postgresql/17.5

# convenient environment variable
export TARGET="/deac/inf/hpcGrp/examples"
export PGDATA="${TARGET}/data-postgres"
export PGUSER=deac
export PGDATABASE=pagila
```

Now you can initialize the database:

```sh
initdb --username $PGUSER --pwprompt
chown $USER:hpcGrp $PGDATA
chmod 750 $PGDATA
```

and add some configuration files:

```sh
cat << EOF > ${PGDATA}/postgresql.conf
listen_addresses = '*'
checkpoint_timeout = 1min
EOF

cat << EOF > ${PGDATA}/pg_hba.conf
# TYPE DATABASE USER CIDR-ADDRESS  METHOD
# host   all      all  0.0.0.0/0     scram-sha-256
host   all      all  samenet       scram-sha-256
local  all      all                scram-sha-256
EOF
```

Start up the Postgres server:

```sh
pg_ctl start -l postgres.log

createdb
```

Let's download the Pagila DB files and uncompress them in the directory:

```sh
git clone git@github.com:devrimgunduz/pagila.git ${TARGET}/pagila
```

Now we are ready to load the Pagila content into our newly created database:

```sh
cat ${TARGET}/pagila/pagila-schema.sql | psql -U $PGUSER -d $PGDATABASE
cat ${TARGET}/pagila/pagila-data.sql   | psql -U $PGUSER -d $PGDATABASE
```

If everything went smoothly, you can now shut down the local database server:

```sh
# pg_ctl status
pg_ctl stop
```

Lastly, remove the unneeded Pagila source files and the initial log:

```sh
rm -rf ${TARGET}/pagila
rm -f ${TARGET}/postgres.log
```


### Example Query

```sql
SELECT
    CONCAT(customer.last_name, ', ', customer.first_name) AS customer,
    address.phone,
    film.title
FROM
    rental
    INNER JOIN customer ON rental.customer_id = customer.customer_id
    INNER JOIN address ON customer.address_id = address.address_id
    INNER JOIN inventory ON rental.inventory_id = inventory.inventory_id
    INNER JOIN film ON inventory.film_id = film.film_id
WHERE
    rental.return_date IS NULL
    AND rental_date < CURRENT_DATE
ORDER BY
    title
LIMIT 5;
```
