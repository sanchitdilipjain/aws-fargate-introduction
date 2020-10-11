## Create a scheduled task in AWS Fargate

<img src="images/image1.jpeg" class="inline"/>
                        
**A scheduled (cron-like) task**
  
  - This all begins with my need to schedule a script to crawl some stock data weekly. In a web service or application, we always have some needs to do a job at   fixed times, dates, or intervals.
  - The most famous job scheduler is <a href="https://en.wikipedia.org/wiki/Cron">cron</a>, which provides a utility for scheduling repetitive tasks on Linux/Unix systems. Cron Expression is commonly used to let you define when tasks should be run. You can check this website <a href="https://crontab.guru/">crontab.guru</a> to configure the cron expression. There are different variants of Cron Expression used in systems, like Jenkins, Kubernetes CronJob, Fargate Scheduled Task etc. Make sure you check its instructions before use.

**AWS Fargate**

  - Fargate is a new managed service for container orchestration provided by AWS. In ECS, we always need to provision the EC2 cluster first before running services. Also, there is an operating cost to maintain the cluster. When there is a change, we need to change both the underlying cluster (the number of EC2 instances) and services (the number of tasks). In Fargate, you don’t need to operate the cluster. You can image Fargate as an unlimited cluster that you can use and you pay as you use.

  - Fargate also provides the ability to run scheduled tasks via CloudWatch Events.

  - There are a couple of other job schedulers:
      - Kubernetes CronJob
      - Airflow (using Celery scheduler)
      - Jenkins

  - Kubernetes CronJob needs to operate a Kubernetes cluster (I haven’t tried AWS EKS yet). Airflow needs to run a machine or a cluster and also is tied to Python. Jenkins can be used as a job scheduler but it is not designed for this.

  - The major advantages of using Fargate I think are:
      - No operation code and cost
      - Support Docker containers
      - Easy for scaling up

  - Plus, Fargate is an extension to ECS, which I am very familiar with.
  
**Create a Fargate scheduled task**

  - #1 Create an empty cluster and a VPC configured with two public subnets.
      - Install ECS-CLI first.

      - Create a cluster configuration
            
            ecs-cli configure --cluster tutorial --region us-east-1 --default-launch-type FARGATE --config-name tutorial

      - Run ecs-cli up.

      - Check that a VPC has a default security group.

  - #2 Create log group, S3 bucket (optional), ECS task execution role, e.g.,
  
         AWSTemplateFormatVersion: '2010-09-09'
         Description: >
           Create S3 bucket.
         Parameters:
           BucketName:
             Type: String
           LogGroupName:
             Type: String
         Resources:
           StockDataBucket:
             Type: AWS::S3::Bucket
             Properties:
               BucketName: !Ref BucketName
           EcsTaskExecutionRole:
             Type: AWS::IAM::Role
             Properties:
               AssumeRolePolicyDocument:
                 Version: "2012-10-17"
                 Statement:
                   -
                     Effect: "Allow"
                     Principal:
                       Service:
                         - "ecs-tasks.amazonaws.com"
                     Action:
                       - "sts:AssumeRole"
               ManagedPolicyArns:
                 - arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
               Path: /
           LogGroup:
             Type: AWS::Logs::LogGroup
             Properties:
               LogGroupName: !Ref LogGroupName
               RetentionInDays: 10

  - #3 Build & push docker image to AWS ECR.
    
    File Makefile:
    
        build:
            docker build -t demo/cron:latest .

        push:
           aws ecr get-login --region us-east-1 > ./ecrlogin.sh
           sed -i -E 's,'"-e none"','""',' ./ecrlogin.sh
           sh ./ecrlogin.sh && rm -rf ./ecrlogin.sh && rm -rf ./ecrlogin.sh-E
           docker tag demo/cron:latest XXX.dkr.ecr.us-east-1.amazonaws.com/cron:${TAG}
           docker push XXX.dkr.ecr.us-east-1.amazonaws.com/cron:${TAG}
           
  - #4 Deploy ECS task definition.
    
    File Makefile:    
    
        task-definition:
           export TAG=${TAG}
           ecs-cli compose --project-name stock-crawler --file ./deploy/docker-compose.yml --ecs-params ./deploy/ecs-params.yml --region us-east-1 create --launch-type FARGATE
           
    File ./deploy/docker-compose.yml:
    
         version: '3'
         services:
           crawler:
             image: XXX.dkr.ecr.us-east-1.amazonaws.com/cron:${TAG}
             env_file:
               - ../.env
             logging:
               driver: awslogs
               options: 
                 awslogs-region: us-east-1
                 awslogs-group: cron
                 awslogs-stream-prefix: ${TAG}

    File ./deploy/ecs-params.yml:
    
         version: 1
         task_definition:
           task_execution_role: {ECS_TASK_EXECUTION_ROLE_NAME}
           ecs_network_mode: awsvpc
           task_size:
             mem_limit: 0.5GB
             cpu_limit: 256
         run_params:
           network_configuration:
             awsvpc_configuration:
               subnets:
                 - {SUBNET_A_NAME}
                 - {SUBNET_B_NAME}
               security_groups:
                 - {SECURITY_GROUP_NAME}
               assign_public_ip: ENABLED
               
     Note: Replace ECS_TASK_EXECUTION_ROLE_NAME, SUBNET_A_NAME, SUBNET_B_NAME, and SECURITY_GROUP_NAME with your parameters.
     
  - #5 Create a scheduled Fargate task.

         AWSTemplateFormatVersion: '2010-09-09'
         Description: >
           Scheduled ECS task.
         Parameters:
           ECSClusterArn:
             Type: String
           ScheduledWorkerTaskArn:
             Type: String

         Resources:
           StockCrawlerTaskSchedule:
             Type: AWS::Events::Rule
             Properties:
               Description: "Cron every 30 mins"
               Name: "cron"
               ScheduleExpression: "cron(0/30 * * * ? *)"
               State: DISABLED
               Targets:
                 - Id: cron-fargate-task
                   RoleArn: !GetAtt TaskSchedulerRole.Arn
                   Arn: !Ref ECSClusterArn
                   EcsParameters:
                     TaskCount: 1
                     TaskDefinitionArn: !Ref ScheduledWorkerTaskArn
           TaskSchedulerRole:
             Type: AWS::IAM::Role
             Properties:
               AssumeRolePolicyDocument:
                 Version: "2012-10-17"
                 Statement:
                   -
                     Effect: "Allow"
                     Principal:
                       Service:
                         - "events.amazonaws.com"
                     Action:
                       - "sts:AssumeRole"
               Path: /
               Policies:
                 - PolicyDocument:
                     Statement:
                       - Effect: "Allow"
                         Condition:
                           ArnEquals:
                             ecs:cluster: !Ref ECSClusterArn
                         Action: "ecs:RunTask"
                         Resource: "*"
                       - Effect: "Allow"
                         Condition:
                           ArnEquals:
                             ecs:cluster: !Ref ECSClusterArn
                         Action:
                           - "iam:ListInstanceProfiles"
                           - "iam:ListRoles"
                           - "iam:PassRole"
                         Resource: "*"
                   PolicyName: "TaskSchedulerPolicy"          

    - Note: From EcsParameters, CloudFormation in Step 5 should support specify parameters, such as LaunchType, NetworkConfiguration, PlatformVersion, for Fargate tasks. However, currently, I don’t think it is finished yet because it throws an error saying keyword does not exist. This is the reason why I set the task to DISABLED.
    
  - #6 Manually update the task config in CloudWatch Event Rules.
  
    - Edit
      - Launch Type: Fargate
      - Platform Version: LATEST
      - Subnets: subnet-001, subnet-002
      - Security Group: sg-001
      - Auto-assign Public IP (MUST): ENABLED
      - Use existing role: TaskSchedulerRole
    - Enable the task
      
**Important Links:**

<a href="https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-cli-tutorial-fargate.html">Amazon ECS CLI</a>

