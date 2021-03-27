KUBECTL_VER = 1.19.9
kubectl-install:		## Install kubectl.
	@kubectl version --client | grep $(KUBECTL_VER); \
		if [ $$? -eq 1 ]; then \
			curl -LOsS https://storage.googleapis.com/kubernetes-release/release/v$(KUBECTL_VER)/bin/linux/amd64/kubectl; \
			chmod +x kubectl; \
			sudo mv kubectl /usr/local/bin; \
			kubectl version --client; \
		else \
            echo "${GREEN} [*] Kubectl already installed ${RESET}"; \
		fi

KUBECTX_VER = 0.9.1
KUBECTX_URL= https://github.com/ahmetb/kubectx/releases/download/v$(KUBECTX_VER)/kubectx_v$(KUBECTX_VER)_linux_x86_64.tar.gz
k8s-kubectx-install:		## Install kubectx
	wget -N $(KUBECTX_URL) -O /tmp/kubectx.tar.gz
	tar zxvf /tmp/kubectx.tar.gz -C /tmp
	sudo mv /tmp/kubectx /usr/local/bin/
	chmod +x /usr/local/bin/kubectx
	kubectx

KUBENS_VER = 0.9.1
KUBENS_URL = https://github.com/ahmetb/kubectx/releases/download/v$(KUBENS_VER)/kubens_v$(KUBENS_VER)_linux_x86_64.tar.gz
k8s-kubens-install:			## Install Kubens
	wget -N $(KUBENS_URL) -O /tmp/kubens.tar.gz
	tar zxvf /tmp/kubens.tar.gz -C /tmp
	sudo mv /tmp/kubens /usr/local/bin/
	chmod +x /usr/local/bin/kubens
	kubens

KUBE_CAPACITY_VER = 0.5.0
k8s-kube-capacity: 	## Install kube-capacity
	wget https://github.com/robscott/kube-capacity/releases/download/$(KUBE_CAPACITY_VER)/kube-capacity_$(KUBE_CAPACITY_VER)_Linux_x86_64.tar.gz -P /tmp
	cd /tmp \
		&& tar zxvf kube-capacity_$(KUBE_CAPACITY_VER)_Linux_x86_64.tar.gz \
		&& sudo mv kube-capacity /usr/local/bin \
		&& kube-capacity

k8s-prepare:	k8s-kubectl-install k8s-kube-capacity k8s-minikube-start ## Install minikube, kubectl, kube-capacity and start a cluster

k8s-deploy-saferwall:	k8s-deploy-nfs-server k8s-deploy-minio k8s-deploy-cb k8s-deploy-nsq k8s-deploy-backend k8s-deploy-consumer k8s-deploy-multiav ## Deploy all stack in k8s

k8s-deploy-nfs-server:	## Deploy NFS server in a newly created k8s cluster
	cd  $(ROOT_DIR)/build/k8s \
	&& kubectl apply -f nfs-server.yaml \
	&& kubectl apply -f samples-pv.yaml \
	&& kubectl apply -f samples-pvc.yaml

k8s-deploy-cb:	## Deploy couchbase in kubernetes cluster
	cd  $(ROOT_DIR)/build/k8s ; \
	kubectl create -f couchbase-sc.yaml ; \
	kubectl create -f couchbase-pv.yaml ; \
	kubectl create -f couchbase-pvc.yaml ; \
	kubectl create -f crd.yaml ; \
	kubectl create -f operator-role.yaml ; \
	kubectl create serviceaccount couchbase-operator --namespace default ; \
	kubectl create rolebinding couchbase-operator --role couchbase-operator --serviceaccount default:couchbase-operator ; \
	kubectl create -f admission.yaml ; \
	kubectl create -f secret.yaml ; \
	kubectl create -f operator-deployment.yaml ; \
	kubectl apply -f couchbase-cluster.yaml  

k8s-deploy-nsq:			## Deploy NSQ in a newly created k8s cluster
	cd  $(ROOT_DIR)/build/k8s \
	&& kubectl apply -f nsqlookupd.yaml \
	&& kubectl apply -f nsqd.yaml \
	&& kubectl apply -f nsqadmin.yaml
	
k8s-deploy-minio:		## Deploy minio
	cd  $(ROOT_DIR)/build/k8s ; \
	kubectl apply -f minio-standalone-pvc.yaml ; \
	kubectl apply -f minio-standalone-deployment.yaml ; \
	kubectl apply -f minio-standalone-service.yaml

k8s-deploy-multiav:		## Deploy multiav in a newly created k8s cluster
	cd  $(ROOT_DIR)/build/k8s \
	&& kubectl apply -f multiav-clamav.yaml \
	&& kubectl apply -f multiav-avira.yaml \
	&& kubectl apply -f multiav-eset.yaml \
	&& kubectl apply -f multiav-kaspersky.yaml \
	&& kubectl apply -f multiav-comodo.yaml \
	&& kubectl apply -f multiav-fsecure.yaml \
	&& kubectl apply -f multiav-bitdefender.yaml \
	&& kubectl apply -f multiav-avast.yaml \
	&& kubectl apply -f multiav-symantec.yaml \
	&& kubectl apply -f multiav-sophos.yaml \
	&& kubectl apply -f multiav-mcafee.yaml \
	&& kubectl apply -f seccomp-profile.yaml \
	&& kubectl apply -f seccomp-installer.yaml \
	&& kubectl apply -f multiav-windefender.yaml

k8s-deploy-backend:		## Deploy backend in kubernetes cluster
	cd  $(ROOT_DIR)/build/k8s ; \
	kubectl delete deployments backend ;\
	kubectl apply -f backend.yaml

k8s-deploy-consumer:		## Deploy consumer in kubernetes cluster
	cd  $(ROOT_DIR)/build/k8s ; \
	kubectl apply -f consumer.yaml

k8s-delete-nsq:
	cd  $(ROOT_DIR)/build/k8s ; \
	kubectl delete svc nsqd nsqadmin nsqlookupd
	kubectl delete deployments nsqadmin 
	kubectl delete deployments nsqadmin

k8s-delete-cb:		## Delete all couchbase related objects from k8s
	kubectl delete cbc cb-saferwall ; \
	kubectl delete deployment couchbase-operator-admission ; \
	kubectl delete deployment couchbase-operator  ; \
	kubectl delete crd couchbaseclusters.couchbase.com  ; \
	kubectl delete secret cb-saferwall-auth ; \
	kubectl delete pvc couchbase-pvc ; \
	kubectl delete pv couchbase-pv ; \
	kubectl delete sc couchbase-sc

k8s-delete-multiav:		## Delete all multiav related objects from k8s
	cd  $(ROOT_DIR)/build/k8s ; \
		kubectl delete deployments avast ; kubectl apply -f multiav-avast.yaml ; \
		kubectl delete deployments avira ; kubectl apply -f multiav-avira.yaml ; \
		kubectl delete deployments bitdefender ; kubectl apply -f multiav-bitdefender.yaml ; \
		kubectl delete deployments comodo ; kubectl apply -f multiav-comodo.yaml ; \
		kubectl delete deployments eset ; kubectl apply -f multiav-eset.yaml ; \
		kubectl delete deployments fsecure ; kubectl apply -f multiav-fsecure.yaml ; \
		kubectl delete deployments symantec ; kubectl apply -f multiav-symantec.yaml ; \
		kubectl delete deployments kaspersky ; kubectl apply -f multiav-kaspersky.yaml ; \
		kubectl delete deployments windefender ; kubectl apply -f multiav-windefender.yaml

k8s-delete:			## delete all
	kubectl delete deployments,service backend -l app=web
	kubectl delete service backend
	kubectl delete service consumer
	kubectl delete deployments consumer ; kubectl apply -f consumer.yaml

	kubectl delete cbc cb-saferwall ; kubectl create -f couchbase-cluster.yaml
	kubectl delete deployments backend ; kubectl apply -f backend.yaml

k8s-pf-kibana:			## Port fordward Kibana
	kubectl port-forward svc/$(SAFERWALL_RELEASE_NAME)-kibana 5601:5601 &
	while true ; do nc -vz 127.0.0.1 5601 ; sleep 5 ; done

k8s-pf-nsq:				## Port fordward NSQ admin service.
	kubectl port-forward svc/$(SAFERWALL_RELEASE_NAME)-nsq-admin 4171:4171 &
	while true ; do nc -vz 127.0.0.1 4171 ; sleep 5 ; done

k8s-pf-grafana:			## Port fordward grafana dashboard service.
	kubectl port-forward deployment/$(SAFERWALL_RELEASE_NAME)-grafana 3000:3000 &
	while true ; do nc -vz 127.0.0.1 3000 ; sleep 5 ; done

k8s-pf-couchbase:		## Port fordward couchbase ui service.
	kubectl port-forward svc/$(SAFERWALL_RELEASE_NAME)-couchbase-cluster-ui 8091:8091 &
	while true ; do nc -vz 127.0.0.1 8091 ; sleep 5 ; done


k8s-pf:					## Port forward all services.
	make k8s-pf-nsq &
	make k8s-pf-couchbase &
	make k8s-pf-grafana &
	make k8s-pf-kibana &

k8s-delete-all-objects: ## Delete all objects
	kubectl delete "$(kubectl api-resources --namespaced=true --verbs=delete -o name | tr "\n" "," | sed -e 's/,$//')" --all

k8s-dump-tls-secrets: ## Dump TLS secrets
	sudo apt install jq -y
	$(eval HELM_RELEASE_NAME := $(shell sudo helm ls --filter saferwall --output json | jq '.[0].name' | tr -d '"'))
	$(eval HELM_SECRET_TLS_NAME := $(HELM_RELEASE_NAME)-tls)
	kubectl get secret $(HELM_SECRET_TLS_NAME) -o jsonpath="{.data['ca\.crt']}" | base64 --decode  >> ca.crt
	kubectl get secret $(HELM_SECRET_TLS_NAME) -o jsonpath="{.data['tls\.crt']}" | base64 --decode  >> tls.crt
	kubectl get secret $(HELM_SECRET_TLS_NAME) -o jsonpath="{.data['tls\.key']}" | base64 --decode  >> tls.key
	openssl pkcs12 -export -out saferwall.p12 -inkey tls.key -in tls.crt -certfile ca.crt

k8s-init-cert-manager: ## Init cert-manager
	# Create the namespace for cert-manager.
	kubectl create namespace cert-manager
	# Install CRDs.
	kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.1.0/cert-manager.crds.yaml
	# Install the chart
	helm install cert-manager jetstack/cert-manager \
		--namespace cert-manager \
		--version v1.2.0
	# Verify the installation.
	kubectl wait --namespace cert-manager \
	--for=condition=ready pod \
	--selector=app.kubernetes.io/instance=cert-manager \
	--timeout=90s

k8s-cert-manager-rm-crd: ## Delete cert-manager crd objects.
	kubectl get crd | grep cert-manager | xargs --no-run-if-empty kubectl delete crd
	kubectl delete namespace cert-manager

k8s-events: ## Get Kubernetes cluster events.
	kubectl get events --sort-by='.metadata.creationTimestamp'


k8s-delete-terminating-pods: ## Force delete pods stuck at `Terminating` status
	for p in $(kubectl get pods | grep Terminating | awk '{print $1}'); \
	 do kubectl delete pod $p --grace-period=0 --force;done

k8s-delete-evicted-pods:	## Clean up all evicted pods
	kubectl get pods | grep Evicted | awk '{print $1}' | xargs kubectl delete pod
