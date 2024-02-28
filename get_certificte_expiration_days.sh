#!/bin/bash
if [[ "$1" =~ ^(.+):[0-9]{1,6}$ ]]; then

#    save servername for SNI
  servername=${BASH_REMATCH[1]}
  
#    if parameter 2 is set use that as servername for SNI
  if (set --; ${2:?})2>/dev/null ; then 
    servername=$2
  fi
  
#    openssl ... command to print expiry date in notAfter=... format
#    $(( expression)) do some math
#    cut -d= -f2 to get text after =
#    date -d '+%s': to get EPOCH seconds value for expiry date
#    date '+%s': to get EPOCH seconds value for today's date 
#    (epochExpiry - epochToday) / 86400: to get difference of 2 EPOCH date-time stamps in number of days
  echo $((($(date -d "$(echo "" | openssl s_client -servername $servername -connect $1 -prexit 2>/dev/null| openssl x509  -noout -enddate | cut -d= -f2)" '+%s') -
 $(date '+%s'))/ 86400 ))
else
  echo "Usage: $0 [hostname or ip]:[port] [servername for sni](optional)"
fi

