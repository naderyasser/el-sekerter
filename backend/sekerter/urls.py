from django.urls import include, path

from secretary import views

urlpatterns = [
    path("", views.root, name="root"),
    path("api/secretary/", include("secretary.urls")),
]
