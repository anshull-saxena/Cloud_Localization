import requests
import json
import datetime
import uuid

# Connection string components
ikey = "a85f50d2-1dae-43d4-b2f8-6de3c54c6bf1"
endpoint = "https://centralindia-0.in.applicationinsights.azure.com/v2/track"

payload = [{
    "name": f"Microsoft.ApplicationInsights.{ikey.replace('-','')}.Message",
    "time": datetime.datetime.utcnow().isoformat() + "Z",
    "iKey": ikey,
    "data": {
        "baseType": "MessageData",
        "baseData": {
            "ver": 2,
            "message": "TranslationMetrics",
            "severityLevel": 1,
            "properties": {
                "test": "from_local_machine"
            }
        }
    }
}]

print("Sending payload...")
response = requests.post(endpoint, json=payload)
print(f"Status Code: {response.status_code}")
print(f"Response: {response.text}")
