import os
import pg8000
import json
import boto3
from botocore.exceptions import ClientError


def get_credentials() -> dict[str, str]:
    secret_name = os.getenv('SECRET_NAME')
    region_name = os.getenv('REGION_NAME')

    # Create a Secrets Manager client
    session = boto3.session.Session()
    client = session.client(service_name='secretsmanager', region_name=region_name)

    try:
        get_secret_value_response = client.get_secret_value(SecretId=secret_name)
    except ClientError as e:
        raise Exception(f"Could not retrieve secret: {str(e)}")

    secret = json.loads(get_secret_value_response['SecretString'])

    return secret


def lambda_handler(event, context):
    # Retrieve the secret containing the database credentials
    secret = get_credentials()
    db_host = os.getenv('DB_HOST')
    db_port = os.getenv('DB_PORT')
    db_user = secret['username']
    db_password = secret['password']
    db_name = os.getenv('DB_NAME')

    try:
        # Connect to the Aurora database
        conn = pg8000.connect(
            host=db_host,
            port=int(db_port),
            user=db_user,
            password=db_password,
            database=db_name
        )

        # If connection is successful, return a success message
        return {
            'statusCode': 200,
            'body': json.dumps('Connection successful!')
        }

    except Exception as e:
        # If connection fails, return the error message
        return {
            'statusCode': 500,
            'body': json.dumps(f'Connection failed: {str(e)}')
        }
    finally:
        # Ensure connection is closed if it was opened
        if 'conn' in locals():
            conn.close()
