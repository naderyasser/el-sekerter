from django.urls import path

from . import views

urlpatterns = [
    path("health", views.health, name="health"),
    path("chat", views.chat_view, name="chat"),
]
