#!/bin/sh

IMAGE_NAME=fr_covidata_engine
docker build -t $IMAGE_NAME . && docker tag $IMAGE_NAME:latest $IMAGE_NAME:`cat VERSION` && docker image ls $IMAGE_NAME
