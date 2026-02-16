import pyodbc
import json

with open("config.json") as f:
    config = json.load(f)

conn = pyodbc.connect(config["SQLConnectionString"])
cursor = conn.cursor()

cursor.execute("SELECT 1")
print(cursor.fetchone())
