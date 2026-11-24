import os
import unittest
from unittest.mock import patch

from hello_world import app


class HelloWorldTests(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()

    def test_root_default_version(self):
        with patch.dict(os.environ, {}, clear=True):
            response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"message": "Hello World", "version": "0.0.0"})

    def test_root_configured_version(self):
        with patch.dict(os.environ, {"APP_VERSION": "1.2.3"}):
            response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"message": "Hello World", "version": "1.2.3"})

    def test_health(self):
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"status": "ok"})


if __name__ == "__main__":
    unittest.main()
