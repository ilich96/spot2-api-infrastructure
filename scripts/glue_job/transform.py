import sys
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from awsglue.job import Job
from pyspark.sql import functions as F
from awsglue.dynamicframe import DynamicFrame

# Initialize Glue context
glueContext = GlueContext(SparkContext.getOrCreate())
spark = glueContext.spark_session

# Get job arguments
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'glue_database_name',
    'glue_table_name',
    'glue_connection_name',
    'aurora_table_name',
])

job = Job(glueContext)
job.init(args['JOB_NAME'], args)

datasource0 = glueContext.create_dynamic_frame.from_catalog(
    database=args['glue_database_name'],
    table_name=args['glue_table_name'],
    transformation_ctx="datasource0"
)

# Convert to DataFrame for transformation
df = datasource0.toDF()
df = df.drop(
    'fid',
    'fid_2',
    'calle_numero',
    'colonia',
    'alcaldia',
    'anio_construccion',
    'instal_esp',
    'valor_unitario_suelo',
)

# Transformation: Apply the mappings
df = df.withColumn(
    'zip_code',
    F.when(F.col('codigo_postal.long').isNull(), 'UNKNOWN')
    .otherwise(F.col('codigo_postal.long').cast('string'))
)
df = df.withColumn(
    'area_colony_type',
    F.when(F.col('cve_vus').isNull(), 'U')
    .otherwise(F.substring('cve_vus', 1, 1))
)
df = df.withColumn(
    'land_price',
    F.when(F.col('valor_suelo').isNull(), 0.0)
    .otherwise(F.col('valor_suelo').cast('float'))
)
df = df.withColumn(
    'ground_area',
    F.when(F.col('sup_terreno').isNull(), 0.0)
    .otherwise(F.col('sup_terreno').cast('float'))
)
df = df.withColumn(
    'construction_area',
    F.when(F.col('sup_construccion').isNull(), 0.0)
    .otherwise(F.col('sup_construccion').cast('float'))
)
df = df.withColumn(
    'subsidy',
    F.when(F.col('subsidio').isNull(), 0.0)
    .otherwise(F.col('subsidio').cast('float'))
)

df = df.drop(
    'codigo_postal',
    'cve_vus',
    'valor_suelo',
    'sup_terreno',
    'sup_construccion',
    'subsidio',
)

# Convert DataFrame back to DynamicFrame for Glue context
mapped_dynamic_frame = DynamicFrame.fromDF(df, glueContext, "mapped_dynamic_frame")

connection_options = {
    "useConnectionProperties": "true",
    "connectionName": args['glue_connection_name'],
    "dbtable": args['aurora_table_name'],
}

# Write the transformed data back to Aurora PostgreSQL
glueContext.write_dynamic_frame.from_options(
    frame=mapped_dynamic_frame,
    connection_type="postgresql",
    connection_options=connection_options,
    transformation_ctx="output"
)

# Commit the job
job.commit()
