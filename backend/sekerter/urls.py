from django.urls import include, path

urlpatterns = [
    path("api/secretary/", include("secretary.urls")),
]
