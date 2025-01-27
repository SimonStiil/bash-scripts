#!/bin/bash
# Get script location. Where to put our files
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
echo "DEBUG Arguments $#"
# Get user Argument
if [ $# -ge 1 ] ; then
USER=$1
SUBJ="/CN=$1"
else
  echo "Not enough arguments: create-user username [group].. "
  exit -1
fi 
# Itterate over group arguments and add them
i=2;
j=$#;
while [ $i -le $j ] ; do
    shift 1;
    SUBJ="$SUBJ/O=$1"
    i=$((i + 1));
done
echo "DEBUG subj $SUBJ"
if [ ! -f $SCRIPT_DIR/$USER.key ] ; then
    # Create a key for our user if it does not already exist
    openssl ecparam -name prime256v1 -genkey -noout -out $SCRIPT_DIR/$USER.key
fi
if [ -f $SCRIPT_DIR/$USER.csr ] ; then
    # Delete previous a temporary Certificate Signing Request(CSR) if it exists (Cleanup)
    rm $SCRIPT_DIR/$USER.csr
fi
# Create a temporary CSR for our user
openssl req -new -key $SCRIPT_DIR/$USER.key -out $SCRIPT_DIR/$USER.csr -subj "$SUBJ"
# Get base64 string for the CSR
CSR=$(cat $SCRIPT_DIR/$USER.csr | base64 | tr -d "\n")
# Create file for certificate request creation
cp $SCRIPT_DIR/template-certificate.yaml $SCRIPT_DIR/$USER-certificate.yaml
sed -i -e "s/USERNAMEFORREPLACEMENT/$USER/g" $SCRIPT_DIR/$USER-certificate.yaml
sed -i -e "s/REQUESTFORREPLACEMENT/$CSR/g" $SCRIPT_DIR/$USER-certificate.yaml
read  -n 1 -p "Apply certificate request to cluster? (y/n):" mainmenuinput
echo ""
if [ $? != 0 ]; then
  exit
fi 
if [ "$mainmenuinput" = "y" ]; then
    # Apply certificate request to cluster
    kubectl apply -f $SCRIPT_DIR/$USER-certificate.yaml
    
    read  -n 1 -p "Approve certificate request in cluster? (y/n):" mainmenuinput
    echo ""
    if [ $? != 0 ]; then
      exit
    fi 
    if [ "$mainmenuinput" = "y" ]; then
        # Approve certificate request in cluster
        kubectl certificate approve $USER
        # Get signed certificate from cluster
        kubectl get csr $USER -o jsonpath='{.status.certificate}'| base64 -d > $SCRIPT_DIR/$USER.crt
        
        read  -n 1 -p "Add user to kubeconfig? (y/n):" mainmenuinput
        echo ""
        if [ $? != 0 ]; then
          exit
        fi 
        if [ "$mainmenuinput" = "y" ]; then
            # Add data to kubeconfig
            kubectl config set-credentials $USER --client-key=$SCRIPT_DIR/$USER.key --client-certificate=$SCRIPT_DIR/$USER.crt --embed-certs=true
        fi
        # Cleanup files
        rm $SCRIPT_DIR/$USER.csr $SCRIPT_DIR/$USER-certificate.yaml
    fi
fi
