import os
import time
import psycopg

DATABASE_URL = os.getenv("DATABASE_URL")

def wait_for_db():
    while True:
        try:
            with psycopg.connect(DATABASE_URL) as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
                    cur.fetchone()
            print("collector: database connected")
            return
        except Exception as e:
            print(f"collector: waiting for db... {e}")
            time.sleep(3)

def main():
    wait_for_db()
    print("collector: started")
    while True:
        print("collector: idle")
        time.sleep(30)

if __name__ == "__main__":
    main()
