// RUN: %clangxx -fsycl -fsycl-targets=%sycl_triple -Dbuffer_new_api_test -std=c++17 %S/Inputs/device_accessor.cpp -o %t.out
// RUN: %HOST_RUN_PLACEHOLDER %t.out
// RUN: %CPU_RUN_PLACEHOLDER %t.out
// RUN: %GPU_RUN_PLACEHOLDER %t.out
// RUN: %ACC_RUN_PLACEHOLDER %t.out
