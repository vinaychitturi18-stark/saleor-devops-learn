pipeline {
    agent any

    environment {
        AWS_REGION        = 'us-east-1'
        AWS_ACCOUNT_ID    = '249297038289'
        ECR_REGISTRY      = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        ECS_CLUSTER       = 'saleor-prod'
        BACKEND_IMAGE     = "${ECR_REGISTRY}/saleor-backend"
        STOREFRONT_IMAGE  = "${ECR_REGISTRY}/saleor-storefront"
    }

    stages {

        stage('Checkout') {
            steps {
                echo "Checked out branch: ${env.BRANCH_NAME}"
            }
        }

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
                    # Update backend service
                    aws ecs update-service \
                        --cluster $ECS_CLUSTER \
                        --service saleor-backend \
                        --force-new-deployment \
                        --region $AWS_REGION

                    # Update worker service
                    aws ecs update-service \
                        --cluster $ECS_CLUSTER \
                        --service saleor-worker \
                        --force-new-deployment \
                        --region $AWS_REGION

                    # Update beat service
                    aws ecs update-service \
                        --cluster $ECS_CLUSTER \
                        --service saleor-beat \
                        --force-new-deployment \
                        --region $AWS_REGION

                    # Update storefront service
                    aws ecs update-service \
                        --cluster $ECS_CLUSTER \
                        --service saleor-storefront \
                        --force-new-deployment \
                        --region $AWS_REGION
                '''
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '''
                    echo "Waiting for services to stabilize..."
                    aws ecs wait services-stable \
                        --cluster $ECS_CLUSTER \
                        --services saleor-backend saleor-storefront \
                        --region $AWS_REGION
                    echo "Deployment successful!"
                '''
            }
        }
    }

    post {
        success {
            echo "Pipeline completed successfully. Deployed build #${BUILD_NUMBER} to prod."
        }
        failure {
            echo "Pipeline failed at stage. Check logs above."
        }
    }
}
