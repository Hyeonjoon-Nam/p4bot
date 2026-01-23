pipeline {
    agent any

    environment {
        // Note: Use forward slashes (/) instead of backslashes (\) to avoid errors.
        HOST_CONFIG_PATH = 'C:/p4bot/config.json'
        HOST_RUNTIME_PATH = 'C:/p4bot/runtime'
    }

    stages {
        stage('Build Image') {
            steps {
                script {
                    echo '🏗️ Building Docker Image...'
                    // 1. Rebuild the Docker image (Overwriting the 'v1' tag)
                    sh 'docker build -t p4bot:v1 .'
                }
            }
        }

        stage('Deploy') {
            steps {
                script {
                    echo '🚀 Deploying new container...'
                    
                    // 2. Remove the existing container (|| true ignores errors if it doesn't exist)
                    sh 'docker rm -f p4bot || true'
                    
                    // 3. Run the new container
                    // Jenkins instructs the Host Docker to run the container mounting the Host's paths.
                    sh """
                        docker run -d --name p4bot --restart unless-stopped \\
                        -v ${HOST_CONFIG_PATH}:/app/config.json \\
                        -v ${HOST_RUNTIME_PATH}:/app/runtime \\
                        p4bot:v1
                    """
                }
            }
        }
    }
}