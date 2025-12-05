#!/bin/bash
# Set all variables to start de script
REGION="europe-west4"
ZONE="europe-west4-c"
MACHINE_SMALL="e2-small"
MACHINE_MEDIUM="e2-medium"
IMAGE_FAMILY_SMALL="debian-12"
IMAGE_FAMILY_MEDIUM="debian-11"
IMAGE_PROJECT="debian-cloud"
TAG="network-lb-tag"
LB_NAME="lb-backend-template"
LB_MIG_NAME="lb-backend-group"
FIREWALL_HC_NAME="fw-allow-health-check"
WWW_FIREWALL_NAME="www-firewall-network-lb"
PORT=80
LB_GLOBAL_STATIC_IP="lb-ipv4-1"
HTTP_HC_NAME="http-basic-check"
BACKEND_SERVICE_NAME="web-backend-service"
NETWORK_ADDRESS_LB_NAME="network-lb-ip-1"
TARGET_POOL_NAME="www-pool"
URL_MAP_NAME="web-map-http"
HTTP_PROXY_NAME="http-lb-proxy"
# Set project config for region an zone
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE

# Create a vms
for VM in web1 web2 web3; do
  gcloud compute instances create $VM \
    --zone=$ZONE \
    --machine-type=$MACHINE_SMALL \
    --image-family=$IMAGE_FAMILY_SMALL \
    --image-project=$IMAGE_PROJECT \
    --tags=$TAG \
    --metadata=startup-script="#!/bin/bash
      apt-get update -y
      apt-get install apache2 -y
      systemctl enable apache2
      systemctl start apache2
      echo '<h3>Web Server: $VM</h3>' > /var/www/html/index.html"
done

# Create a firewall rule to allow external traffic to the VM instances 
gcloud compute firewall-rules create $WWW_FIREWALL_NAME   --target-tags $TAG --allow tcp:$PORT

# get IPs VM to validate
gcloud compute instances list

echo usan "curl http://[IP_ADDRESS]"


# Create an target-pool
gcloud compute target-pools create $TARGET_POOL_NAME --region $REGION

# create a address IP to the loadbalancer
gcloud compute addresses create $NETWORK_ADDRESS_LB_NAME --region $REGION


gcloud compute http-health-checks create basic-check


# # create a new loadbalancer 
gcloud compute instance-templates create $LB_NAME \
   --region=$REGION \
   --network=default \
   --subnet=default \
   --tags=allow-health-check \
   --machine-type=$MACHINE_MEDIUM \
   --image-family=$IMAGE_FAMILY_MEDIUM \
   --image-project=$IMAGE_PROJECT \
   --metadata=startup-script='#!/bin/bash
     apt-get update
     apt-get install apache2 -y
     a2ensite default-ssl
     a2enmod ssl
     vm_hostname="$(curl -H "Metadata-Flavor:Google" \
     http://169.254.169.254/computeMetadata/v1/instance/name)"
     echo "Page served from: $vm_hostname" | \
     tee /var/www/html/index.html
     systemctl restart apache2'




# create an Instance group
gcloud compute instance-groups managed create $LB_MIG_NAME --template=$LB_NAME --size=2 --zone=$ZONE

# Create an HEALTH CHECK
gcloud compute firewall-rules create $FIREWALL_HC_NAME \
  --network=default \
  --action=allow \
  --direction=ingress \
  --source-ranges=130.211.0.0/22, 35.191.0.0/16 \
  --target-tags=allow-health-check \
  --rules=tcp:$PORT

# create a loadbalencer external global static
gcloud compute addresses create $LB_GLOBAL_STATIC_IP --ip-version=IPV4 --global

# Validate the external IP was reserved
gcloud compute addresses describe $LB_GLOBAL_STATIC_IP --format="get(address)" --global

# create a Health check for loadbalancer
gcloud compute health-checks create http $HTTP_HC_NAME --port $PORT

# Update target pools
gcloud compute target-pools create $TARGET_POOL_NAME --region $REGION --http-health-check basic-check

# add vms to target pool
gcloud compute target-pools add-instances $TARGET_POOL_NAME --instances www1,www2,www3

# Create a BAckend Services
gcloud compute backend-services create $BACKEND_SERVICE_NAME \
  --protocol=HTTP \
  --port-name=http \
  --health-checks=http-basic-check \
  --global

# Add Instance Group in Backend service
gcloud compute backend-services add-backend $BACKEND_SERVICE_NAME \
  --instance-group=$LB_MIG_NAME \
  --instance-group-zone=$$ZONE \
  --global

# Create an URL MAP
gcloud compute url-maps create $URL_MAP_NAME --default-service web-backend-service

# Create an HTTP PROXY
gcloud compute target-http-proxies create $HTTP_PROXY_NAME --url-map $URL_MAP_NAME