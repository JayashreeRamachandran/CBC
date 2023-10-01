from django.urls import path
from . import views

urlpatterns = [
    path('', views.createAgent, name='create'),
    path('list/', views.listagents, name='list_agents'),
    path('run/', views.run_script, name='run_file')
    # Add other URL patterns as needed
]