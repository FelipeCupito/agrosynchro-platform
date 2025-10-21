def add_cors_headers(response):
    """Add CORS headers to the response"""
    if "headers" not in response:
        response["headers"] = {}
    
    response["headers"].update({
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "OPTIONS,GET,POST",
        "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token"
    })
    
    return response