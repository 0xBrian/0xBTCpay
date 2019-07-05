#!/bin/bash

source /usr/local/share/chruby/chruby.sh
chruby ruby

case $1 in
  stream)
    bundle exec ruby stream.rb
    ;;
  payments)
    RACK_ENV=production bundle exec ruby payments.rb
    ;;
  payments_worker)
    RACK_ENV=production bundle exec ruby payments_worker.rb
    ;;
  *)
    echo "err"
    ;;
esac
