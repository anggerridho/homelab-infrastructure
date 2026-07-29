apiMananger="registry.localhostaddr.biz.id/api-manager:1.1"
alertSVC="registry.localhostaddr.biz.id/alert-service:0.9"

# docker build --no-cache -t ${apiMananger} ./api-manager

docker build --no-cache -t ${alertSVC} ./alert-service

# docker push ${apiMananger}

docker push ${alertSVC}
