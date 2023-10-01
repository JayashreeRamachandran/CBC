FROM python:3.11

# Set environment variables for your Django project
ENV DJANGO_SETTINGS_MODULE="ILM_CBC.settings"
ENV PYTHONUNBUFFERED 1

# Set the working directory in the container
WORKDIR /app

# Copy the requirements.txt file into the container
COPY requirements.txt /app/

# Install project dependencies
RUN pip install -r requirements.txt

# Copy the Django project code into the container
COPY . /app/

# Giving permissions
RUN set -x \
    && chmod +x /app/CBC/script/*


# Add host ip into allowed hosts of settings.py
CMD ["/bin/bash", "/app/CBC/script/start.sh"]

# Expose the port your Django app will run on (default is 8000)
EXPOSE 8000

# Run the Django development server when the container starts
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
