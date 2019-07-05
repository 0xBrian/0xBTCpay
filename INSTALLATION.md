## Installation (Ubuntu 18.04 x64)

### As root:
```
apt update
apt install -y build-essential mysql-server libmysqlclient-dev redis-server
```

Check out the 0xbtcpay repo.
```
git clone https://github.com/0xBrian/0xbtcpay.git
```

Go to https://github.com/postmodern/ruby-install/releases .
Set a variable `V` to the latest version:
```
V=0.7.0
```

Now do the installation:
```
wget -O ruby-install-$V.tar.gz https://github.com/postmodern/ruby-install/archive/v$V.tar.gz
tar -xzvf ruby-install-$V.tar.gz
cd ruby-install-$V
make install
ruby-install ruby 2.6.3
cd -
```

Go to https://github.com/postmodern/chruby/releases .
Set a variable `V` to the latest version:
```
V=0.3.9
```

Now do the installation:
```
wget -O chruby-$V.tar.gz https://github.com/postmodern/chruby/archive/v$V.tar.gz
tar -xzvf chruby-$V.tar.gz
cd chruby-$V
make install
cd -
```

If you haven't previously set up MySQL,
```
mysql_secure_installation
```

Generate a secure password.
```
source /usr/local/share/chruby/chruby.sh
chruby 2.6.3
ruby -r securerandom -e 'puts SecureRandom.hex'
```
Set that password in `~root/.my.cnf`.
```
[client]
user=root
password=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Create a MySQL database and user. At `mysql` prompt:
```
create database 0xbtcpay;
create user 0xbtcpay@localhost identified by "0xbtcpay";
grant all on 0xbtcpay.* to 0xbtcpay@localhost;
flush privileges;
```

Cause services to be started at boot time.
```
cp systemd/*.service /etc/systemd/system/
systemctl enable stream payments payments_worker
```

Create a user.
```
useradd -m -d /home/0xbtcpay -s /bin/bash _0xbtcpay
```

Copy the 0xbtcpay repo.
```
cp -R 0xbtcpay /home/0xbtcpay
chown -R _0xbtcpay:_0xbtcpay /home/0xbtcpay
```

### As the webapp user `_0xbtcpay`:

Add the following lines to `~/.profile`:
```
source /usr/local/share/chruby/chruby.sh
chruby 2.6.3
```

Update the environment.
```
source ~/.profile
```

Install library dependencies.
```
gem install bundler
cd 0xbtcpay # where the GitHub repo has been checked out
bundle install --path vendor/bundle
```

Copy the example configuration files to the real ones.
```
cp config.example.yml config.yml
cp database.example.yml database.yml
```
Configure at least `config.yml` and add your preferred web3 providers, e.g.
Infura. Please take special note of the comments indicating which type of URL
goes where. One must be `wss://` and the other must be `https://`.

Run database migrations.
```
bundle exec sequel -E -m migrations/ database.yml
```

### As root:

Start the services.
```
systemctl start stream payments payments_worker
```
