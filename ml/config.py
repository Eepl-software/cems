import os
from typing import Dict, Any

class Config:
    """Base configuration class"""
    
    # API Configuration
    API_HOST = os.getenv('API_HOST', '0.0.0.0')
    API_PORT = int(os.getenv('API_PORT', 8000))
    API_WORKERS = int(os.getenv('API_WORKERS', 1))
    
    # OCR Configuration
    TESSERACT_CONFIG = os.getenv('TESSERACT_CONFIG', r'--oem 3 --psm 6')
    OCR_TIMEOUT = int(os.getenv('OCR_TIMEOUT', 30))  # seconds
    
    # Image Processing
    MAX_IMAGE_SIZE = int(os.getenv('MAX_IMAGE_SIZE', 10 * 1024 * 1024))  # 10MB
    MIN_IMAGE_RESOLUTION = int(os.getenv('MIN_IMAGE_RESOLUTION', 200))
    SUPPORTED_FORMATS = ['image/jpeg', 'image/png', 'image/bmp', 'image/tiff']
    
    # Validation
    WEIGHT_VALIDATION_TOLERANCE = float(os.getenv('WEIGHT_VALIDATION_TOLERANCE', 0.1))  # 10%
    
    # Logging
    LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
    LOG_FORMAT = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    
    # CORS
    CORS_ORIGINS = os.getenv('CORS_ORIGINS', '*').split(',')
    
    # Performance
    ENABLE_CACHING = os.getenv('ENABLE_CACHING', 'false').lower() == 'true'
    CACHE_TTL = int(os.getenv('CACHE_TTL', 300))  # 5 minutes
    
    @classmethod
    def get_config(cls) -> Dict[str, Any]:
        """Get all configuration as dictionary"""
        return {
            key: getattr(cls, key)
            for key in dir(cls)
            if not key.startswith('_') and not callable(getattr(cls, key))
        }

class DevelopmentConfig(Config):
    """Development configuration"""
    DEBUG = True
    LOG_LEVEL = 'DEBUG'
    API_WORKERS = 1

class ProductionConfig(Config):
    """Production configuration"""
    DEBUG = False
    LOG_LEVEL = 'INFO'
    API_WORKERS = 4
    CORS_ORIGINS = ['https://your-domain.com']

class TestingConfig(Config):
    """Testing configuration"""
    DEBUG = True
    LOG_LEVEL = 'DEBUG'
    OCR_TIMEOUT = 10
    MAX_IMAGE_SIZE = 1024 * 1024  # 1MB for testing

# Configuration factory
def get_config():
    """Get configuration based on environment"""
    env = os.getenv('ENVIRONMENT', 'development').lower()
    
    if env == 'production':
        return ProductionConfig()
    elif env == 'testing':
        return TestingConfig()
    else:
        return DevelopmentConfig()

# Global config instance
config = get_config()