build:
    docker build -t demo/cron:latest .

push:
   aws ecr get-login --region us-east-1 > ./ecrlogin.sh
   sed -i -E 's,'"-e none"','""',' ./ecrlogin.sh
   sh ./ecrlogin.sh && rm -rf ./ecrlogin.sh && rm -rf ./ecrlogin.sh-E
   docker tag demo/cron:latest XXX.dkr.ecr.us-east-1.amazonaws.com/cron:${TAG}
   docker push XXX.dkr.ecr.us-east-1.amazonaws.com/cron:${TAG}

task-definition:
   export TAG=${TAG}
   ecs-cli compose --project-name cron --file ./deploy/docker-compose.yml --ecs-params ./deploy/ecs-params.yml --region us-east-1 create --launch-type FARGATE