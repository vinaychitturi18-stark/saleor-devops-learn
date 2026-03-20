pipeline {
    agent any

    environment {
        AWS_REGION       = 'us-east-1'
        AWS_ACCOUNT_ID   = '249297038289'
        ECR_REGISTRY     = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        ECS_CLUSTER      = 'saleor-prod'
        BACKEND_IMAGE    = "${ECR_REGISTRY}/saleor-backend"
        STOREFRONT_IMAGE = "${ECR_REGISTRY}/saleor-storefront"
        HOME             = '/var/lib/jenkins'
    }

    stages {

        stage('Build Backend') {
            steps {
                dir('saleor') {
                    sh '''
                        docker build -t $BACKEND_IMAGE:$BUILD_NUMBER .
                        docker tag $BACKEND_IMAGE:$BUILD_NUMBER $BACKEND_IMAGE:latest
                    '''
                }
            }
        }

        stage('Build Storefront') {
            steps {
                dir('saleor-storefront') {
                    sh '''
                        docker build -t $STOREFRONT_IMAGE:$BUILD_NUMBER .
                        docker tag $STOREFRONT_IMAGE:$BUILD_NUMBER $STOREFRONT_IMAGE:latest
                    '''
                }
            }
        }

        stage('Push Images to ECR') {
            steps {
                sh '''
                    docker push $BACKEND_IMAGE:$BUILD_NUMBER
                    docker push $BACKEND_IMAGE:latest
                    docker push $STOREFRONT_IMAGE:$BUILD_NUMBER
                    docker push $STOREFRONT_IMAGE:latest
                '''
            }
        }

        stage('Deploy to ECS') {
            steps {
                sh '''
                    aws ecs update-service --cluster $ECS_CLUSTER --service saleor-backend-prod --force-new-deployment --region $AWS_REGION
                    aws ecs update-service --cluster $ECS_CLUSTER --service saleor-worker-prod --force-new-deployment --region $AWS_REGION
                    aws ecs update-service --cluster $ECS_CLUSTER --service saleor-beat-prod --force-new-deployment --region $AWS_REGION
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
                        --services saleor-backend-prod saleor-storefront-prod \
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
    }
}
