apiMananger="registry.localhostaddr.biz.id/api-manager:0.8"
alertSVC="registry.localhostaddr.biz.id/alert-service:0.4"

docker build -t ${apiMananger} ./api-manager

docker build -t ${alertSVC} ./alert-service

docker push ${apiMananger}

docker push ${alertSVC}
