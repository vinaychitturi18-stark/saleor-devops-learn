pipeline {
    agent any

    environment {
        AWS_REGION       = 'us-east-1'
        AWS_ACCOUNT_ID   = '249297038289'
        ECR_REGISTRY     = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        ECS_CLUSTER      = 'saleor-prod'
        BACKEND_IMAGE    = "${ECR_REGISTRY}/saleor-backend"
        DASHBOARD_IMAGE  = "${ECR_REGISTRY}/saleor-dashboard"
        STOREFRONT_IMAGE = "${ECR_REGISTRY}/saleor-storefront"
        DOCKER_CONFIG    = "${WORKSPACE}/.docker"
    }

    stages {

        stage('ECR Login') {
            steps {
                sh '''
                    mkdir -p $DOCKER_CONFIG
                    aws ecr get-login-password --region $AWS_REGION | \
                        docker --config $DOCKER_CONFIG login --username AWS --password-stdin $ECR_REGISTRY
                '''
            }
        }

        stage('Setup Buildx') {
            steps {
                sh '''
                    docker buildx use armbuilder || docker buildx create --name armbuilder --use
                    docker buildx inspect --bootstrap
                    ln -sfn $HOME/.docker/buildx $DOCKER_CONFIG/buildx
                '''
            }
        }

        stage('Build & Push Backend') {
            steps {
                dir('saleor') {
                    sh '''
                        docker --config $DOCKER_CONFIG buildx build \
                            --platform linux/arm64 \
                            --builder armbuilder \
                            -t $BACKEND_IMAGE:$BUILD_NUMBER \
                            -t $BACKEND_IMAGE:latest \
                            --push .
                    '''
                }
            }
        }

        stage('Build & Push Dashboard') {
            steps {
                dir('saleor-dashboard') {
                    sh '''
                        docker --config $DOCKER_CONFIG buildx build \
                            --platform linux/arm64 \
                            --builder armbuilder \
                            --build-arg API_URL=https://learnwithvinay.in/graphql/ \
                            --build-arg APP_MOUNT_URI=/dashboard/ \
                            -t $DASHBOARD_IMAGE:$BUILD_NUMBER \
                            -t $DASHBOARD_IMAGE:latest \
                            --push .
                    '''
                }
            }
        }

        stage('Build & Push Storefront') {
            steps {
                dir('saleor-storefront') {
                    sh '''
                        docker --config $DOCKER_CONFIG buildx build \
                            --platform linux/arm64 \
                            --builder armbuilder \
                            -t $STOREFRONT_IMAGE:$BUILD_NUMBER \
                            -t $STOREFRONT_IMAGE:latest \
                            --push .
                    '''
                }
            }
        }

        stage('Deploy to ECS') {
            steps {
                sh '''
                    aws ecs update-service --cluster $ECS_CLUSTER --service saleor-backend-prod --force-new-deployment --region $AWS_REGION
                    aws ecs update-service --cluster $ECS_CLUSTER --service saleor-worker-prod --force-new-deployment --region $AWS_REGION
                    aws ecs update-service --cluster $ECS_CLUSTER --service saleor-beat-prod --force-new-deployment --region $AWS_REGION
                    aws ecs update-service --cluster $ECS_CLUSTER --service saleor-dashboard-prod --force-new-deployment --region $AWS_REGION
                    aws ecs update-service --cluster $ECS_CLUSTER --service saleor-storefront-prod --force-new-deployment --region $AWS_REGION
                '''
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '''
                    echo "Waiting for services to stabilize..."
                    aws ecs wait services-stable \
                        --cluster $ECS_CLUSTER \
                        --services saleor-backend-prod saleor-dashboard-prod saleor-storefront-prod \
                        --region $AWS_REGION
                    echo "Deployment successful!"
                '''
            }
        }
    }

    post {
        success {
            echo "Build #${BUILD_NUMBER} deployed to prod successfully."
        }
        failure {
            echo "Pipeline failed. Check logs above."
        }
        always {
            sh 'rm -rf $DOCKER_CONFIG'
        }
    }
}
