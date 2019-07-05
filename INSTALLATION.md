## Installation (Ubuntu 18.04 x64)

### As root:
```
apt update
apt install -y build-essential mysql-server libmysqlclient-dev redis-server
```

We are going to install Ruby using ruby-install, and we will choose the Ruby version to run with chruby. Using these utilities will allow 0xbtcpay to run with a recent version of Ruby, rather than trying to work with the older version of Ruby that Ubuntu installs by default. (Our Ruby will be installed to `/opt/rubies/ruby-2.6.3`.)

Install ruby-install, the Ruby installer: (You can check for newer versions at https://github.com/postmodern/ruby-install/releases if you want, but this version should work fine.)
```
V=0.7.0
wget -O ruby-install-$V.tar.gz https://github.com/postmodern/ruby-install/archive/v$V.tar.gz
tar -xzvf ruby-install-$V.tar.gz
cd ruby-install-$V
make install
cd -
```

Install chruby, the Ruby version chooser: (You can check for newer versions at https://github.com/postmodern/chruby/releases if you want, but this version should work fine.)
```
V=0.3.9
wget -O chruby-$V.tar.gz https://github.com/postmodern/chruby/archive/v$V.tar.gz
tar -xzvf chruby-$V.tar.gz
cd chruby-$V
make install
cd -
```

Install the latest Ruby:
```
ruby-install ruby
```

If you haven't previously set up MySQL, we need to do it now. First, use the following command to generate a secure password and show it on the screen. Copy it now because we will need to paste it soon:
```
openssl rand -hex 10
```
Now run the following command to set the MySQL root password and improve MySQL's security. Paste in the password printed by the previous command. Answer `y` to all of the questions.
```
mysql_secure_installation
```

Create the file `~root/.my.cnf` and put the following content into it. (Replace `xxx...` with the password from above.) This allows the root Linux user to run the `mysql` command without typing a password every time.
```
[client]
user=root
password=xxxxxxxxxxxxxxxxxxxx
```

Create a MySQL database and user. Run the `mysql` command and paste these MySQL commands:
```
create database 0xbtcpay;
create user 0xbtcpay@localhost identified by "0xbtcpay";
grant all on 0xbtcpay.* to 0xbtcpay@localhost;
flush privileges;
```

Create a Linux user. (We have to put an underscore at the front of the username because Linux doesn't allow usernames starting with numbers.)
```
useradd -m -d /home/0xbtcpay -s /bin/bash _0xbtcpay
```

### As the webapp user `_0xbtcpay`:


Add the following lines to `~/.profile` to use the Ruby we installed:
```
source /usr/local/share/chruby/chruby.sh
chruby ruby
```

Update the environment. You can execute this command or log out and log back in.
```
source ~/.profile
```

Check out the 0xbtcpay repo.
```
git clone https://github.com/0xBrian/0xbtcpay.git
cd 0xbtcpay # where the GitHub repo has been checked out
```

Install library dependencies.
```
gem install bundler
bundle install --path vendor/bundle
```

Copy the example configuration files to the real ones.
```
cp config.example.yml config.yml
cp database.example.yml database.yml
```
Configure at least `config.yml` and add your preferred web3 providers, e.g.
Infura. Please take special note of the comments indicating which type of URL
goes where. The first must be `wss://` and the other must be `https://`.

Run database migrations.
```
bundle exec sequel -E -m migrations/ database.yml
```

### As root:

Cause 0xbtcpay services to be started at boot time.
```
cd /home/0xbtcpay/0xbtcpay/
cp systemd/*.service /etc/systemd/system/
systemctl enable stream payments payments_worker
```

Start the services.
```
systemctl start stream payments payments_worker
```
