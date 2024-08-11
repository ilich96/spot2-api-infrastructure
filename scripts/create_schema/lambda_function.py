import os
import pg8000
import json
import boto3
from botocore.exceptions import ClientError


def get_credentials() -> dict[str, str]:
    secret_name = os.getenv('SECRET_NAME')
    region_name = os.getenv('REGION_NAME')

    session = boto3.session.Session()
    client = session.client(service_name='secretsmanager', region_name=region_name)

    try:
        get_secret_value_response = client.get_secret_value(SecretId=secret_name)
    except ClientError as e:
        raise Exception(f"Could not retrieve secret: {str(e)}")

    return json.loads(get_secret_value_response['SecretString'])


def lambda_handler(event, context):
    credentials = get_credentials()
    db_host = os.getenv('DB_HOST')
    db_port = os.getenv('DB_PORT')
    db_user = credentials['username']
    db_password = credentials['password']
    db_name = os.getenv('DB_NAME')

    conn = pg8000.connect(
        host=db_host,
        port=int(db_port),
        user=db_user,
        password=db_password,
        database=db_name
    )

    create_table_query = """
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT FROM information_schema.tables 
                WHERE table_name = 'land_uses' AND table_schema = 'public'
            ) THEN
                CREATE TABLE public.land_uses (
                    id SERIAL PRIMARY KEY,
                    zip_code VARCHAR(10) NOT NULL,
                    area_colony_type CHAR(1) NOT NULL,
                    land_price FLOAT NOT NULL,
                    ground_area FLOAT NOT NULL,
                    construction_area FLOAT NOT NULL,
                    subsidy FLOAT
                );
                CREATE INDEX idx_land_uses_zip_code ON public.land_uses(zip_code);
                CREATE INDEX idx_land_uses_area_colony_type ON public.land_uses(area_colony_type);
            END IF;
        END $$;
        """

    with conn.cursor() as cursor:
        cursor.execute(create_table_query)
        conn.commit()

    conn.close()

    return {
        'statusCode': 200,
        'body': 'Table creation query executed successfully'
    }
